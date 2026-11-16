package org.otzaria.otzaria

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

internal class DownloadNetworkChannel(context: Context, messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val channel = EventChannel(messenger, "otzaria/download_network")
    private val manager by lazy { context.getSystemService(ConnectivityManager::class.java) }
    private val handler by lazy { Handler(Looper.getMainLooper()) }
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var sink: EventChannel.EventSink? = null
    private val state = DownloadNetworkState()

    init {
        channel.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null)
        sink = events
        val listener = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                handler.post {
                    if (sink !== events) return@post
                    events.success(state.onAvailable(network))
                }
            }

            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                handler.post {
                    if (sink === events) {
                        state.onCapabilities(
                            network,
                            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
                        )?.let(events::success)
                    }
                }
            }

            override fun onLost(network: Network) {
                handler.post {
                    if (sink === events) state.onLost(network)?.let(events::success)
                }
            }
        }
        manager.registerDefaultNetworkCallback(listener)
        callback = listener
        val currentNetwork = manager.activeNetwork
        state.onAvailable(currentNetwork)
        val current = currentNetwork?.let(manager::getNetworkCapabilities)
        val allowed = current?.let {
            state.onCapabilities(
                currentNetwork,
                it.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                it.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
            )
        } ?: false
        events.success(allowed)
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        callback?.let(manager::unregisterNetworkCallback)
        callback = null
        state.reset()
    }

    fun dispose() {
        onCancel(null)
        channel.setStreamHandler(null)
    }
}
