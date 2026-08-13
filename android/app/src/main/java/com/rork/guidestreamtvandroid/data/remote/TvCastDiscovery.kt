package com.rork.guidestreamtvandroid.data.remote

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import java.util.Collections

/**
 * Roku-only LAN discovery service — Android counterpart of the iOS
 * `TVCastDiscovery` when called with `rokuOnly: true`.
 *
 * Walks the local /24 subnet hitting Roku ECP on port 8060, parsing the
 * XML device-info response to extract the device name and stable ID.
 * Does NOT implement mDNS, NSD, SSDP, or Google Cast discovery.
 */
data class DiscoveredTvDevice(
    val id: String,
    val name: String,
    val host: String?,
    val port: Int?,
)

class TvCastDiscovery {
    private val _devices = MutableStateFlow<List<DiscoveredTvDevice>>(emptyList())
    val devices: StateFlow<List<DiscoveredTvDevice>> = _devices.asStateFlow()

    private val _isScanning = MutableStateFlow(false)
    val isScanning: StateFlow<Boolean> = _isScanning.asStateFlow()

    private val _localIpv4 = MutableStateFlow<String?>(null)
    val localIpv4: StateFlow<String?> = _localIpv4.asStateFlow()

    private val _scannedHosts = MutableStateFlow(0)
    val scannedHosts: StateFlow<Int> = _scannedHosts.asStateFlow()

    private val _totalHosts = MutableStateFlow(0)
    val totalHosts: StateFlow<Int> = _totalHosts.asStateFlow()

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var scanJob: Job? = null

    fun start() {
        if (_isScanning.value) return
        _isScanning.value = true
        _devices.value = emptyList()
        _localIpv4.value = null
        _scannedHosts.value = 0
        _totalHosts.value = 0

        scanJob = scope.launch {
            val localIP = localIPv4Address()
            if (localIP == null) {
                _isScanning.value = false
                return@launch
            }
            _localIpv4.value = localIP

            val parts = localIP.split(".")
            if (parts.size != 4) {
                _isScanning.value = false
                return@launch
            }
            val prefix = "${parts[0]}.${parts[1]}.${parts[2]}."
            val allHosts = (1..254).map { "$prefix$it" }
            _totalHosts.value = allHosts.size

            val batchSize = 128
            val limitedDispatcher = Dispatchers.IO.limitedParallelism(128)

            var index = 0
            while (index < allHosts.size) {
                if (!isActive) break
                val end = minOf(index + batchSize, allHosts.size)
                val batch = allHosts.subList(index, end)

                coroutineScope {
                    batch.map { host ->
                        async(limitedDispatcher) {
                            val device = probeHost(host)
                            if (device != null) {
                                _devices.update { current ->
                                    if (current.any { it.id == device.id }) current
                                    else current + device
                                }
                            }
                            _scannedHosts.update { it + 1 }
                        }
                    }.awaitAll()
                }
                index = end
            }
            _isScanning.value = false
        }
    }

    fun stop() {
        scanJob?.cancel()
        _isScanning.value = false
    }

    /**
     * Probes a user-entered IP for Roku ECP (:8060). Returns true if a device
     * was added. Uses a 3000ms timeout.
     */
    suspend fun probeManualHost(rawHost: String): Boolean {
        val host = rawHost.trim()
        if (host.isEmpty()) return false

        return withContext(Dispatchers.IO) {
            try {
                val socket = Socket()
                socket.connect(InetSocketAddress(host, 8060), 3000)
                socket.soTimeout = 3000
                val request = "GET /query/device-info HTTP/1.0\r\nHost: $host\r\nConnection: close\r\n\r\n"
                socket.getOutputStream().write(request.toByteArray())
                socket.getOutputStream().flush()

                val reader = BufferedReader(InputStreamReader(socket.getInputStream()))
                val response = StringBuilder()
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    response.append(line).append("\n")
                    if (response.length > 8192) break
                }
                socket.close()

                val body = response.toString()
                if (!body.lowercase().contains("roku")) return@withContext false

                val name = extractTag("user-device-name", body)
                    ?: extractTag("friendly-device-name", body)
                    ?: extractTag("model-name", body)
                    ?: "Roku ($host)"
                val udn = extractTag("device-id", body) ?: host
                val device = DiscoveredTvDevice(
                    id = "roku-$udn",
                    name = name,
                    host = host,
                    port = 8060,
                )
                _devices.update { current ->
                    if (current.any { it.id == device.id }) current
                    else current + device
                }
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun probeHost(host: String): DiscoveredTvDevice? {
        return try {
            val socket = Socket()
            socket.connect(InetSocketAddress(host, 8060), 800)
            socket.soTimeout = 800
            val request = "GET /query/device-info HTTP/1.0\r\nHost: $host\r\nConnection: close\r\n\r\n"
            socket.getOutputStream().write(request.toByteArray())
            socket.getOutputStream().flush()

            val reader = BufferedReader(InputStreamReader(socket.getInputStream()))
            val response = StringBuilder()
            var line: String?
            while (reader.readLine().also { line = it } != null) {
                response.append(line).append("\n")
                if (response.length > 8192) break
            }
            socket.close()

            val body = response.toString()
            if (!body.lowercase().contains("roku")) return null

            val name = extractTag("user-device-name", body)
                ?: extractTag("friendly-device-name", body)
                ?: extractTag("model-name", body)
                ?: "Roku ($host)"
            val udn = extractTag("device-id", body) ?: host
            DiscoveredTvDevice(
                id = "roku-$udn",
                name = name,
                host = host,
                port = 8060,
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun extractTag(tag: String, xml: String): String? {
        val open = "<$tag>"
        val close = "</$tag>"
        val start = xml.indexOf(open)
        if (start == -1) return null
        val contentStart = start + open.length
        val end = xml.indexOf(close, contentStart)
        if (end == -1) return null
        return xml.substring(contentStart, end).trim()
    }

    // MARK: - Local IPv4 discovery

    /**
     * Resolves the local IPv4 by enumerating [NetworkInterface.getNetworkInterfaces],
     * skipping loopback and down interfaces. Ranks candidates with the same
     * rules as the iOS `rankIPv4`: prefer `wlan0`, then any `wlan`/`eth`,
     * prefer RFC1918 private addresses, and rank 169.254.x.x link-local last.
     */
    private fun localIPv4Address(): String? {
        val candidates = mutableListOf<Pair<String, String>>()

        try {
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (intf in interfaces) {
                if (!intf.isUp || intf.isLoopback) continue
                val name = intf.name
                val blockedPrefixes = listOf("awdl", "llw", "utun", "ipsec", "pdp_ip", "rmnet", "lo", "bridge")
                if (blockedPrefixes.any { name.startsWith(it) }) continue

                val addresses = Collections.list(intf.inetAddresses)
                for (addr in addresses) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        val ip = addr.hostAddress ?: continue
                        val cleanIp = ip.substringBefore("%")
                        candidates.add(name to cleanIp)
                    }
                }
            }
        } catch (_: Exception) {
            return null
        }

        return candidates.minByOrNull { rankIPv4(it.second, it.first) }?.second
    }

    private fun rankIPv4(ip: String, name: String): Int {
        val isWlan0 = name == "wlan0"
        val isWlanOrEth = name.startsWith("wlan") || name.startsWith("eth")
        val isPriv = isPrivateLAN(ip)
        val isLink = ip.startsWith("169.254.")

        if (isPriv) {
            if (isWlan0) return 0
            if (isWlanOrEth) return 1
            return 4
        }
        if (!isLink) {
            if (isWlan0) return 2
            if (isWlanOrEth) return 3
            return 5
        }
        if (isWlan0) return 6
        if (isWlanOrEth) return 7
        return 8
    }

    private fun isPrivateLAN(ip: String): Boolean {
        if (ip.startsWith("192.168.")) return true
        if (ip.startsWith("10.")) return true
        if (ip.startsWith("172.")) {
            val parts = ip.split(".")
            if (parts.size >= 2) {
                val second = parts[1].toIntOrNull()
                if (second != null && second in 16..31) return true
            }
        }
        return false
    }
}
