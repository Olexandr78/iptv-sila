package ua.iptvsila

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AlertDialog
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

private data class Channel(val name: String, val group: String, val url: String, val headers: Map<String, String> = emptyMap())
private data class Source(val name: String, val description: String, val url: String)

class MainActivity : AppCompatActivity() {
    private val sources = listOf(
        Source("iptv-org — Украина", "Открытые каналы Украины", "https://iptv-org.github.io/iptv/countries/ua.m3u"),
        Source("IPTV Nexus — Украина", "181 украинский канал, автоматически обновляемый список", "https://dearbulut.github.io/iptv/playlists/country/ua.m3u"),
        Source("Free-TV — Украина", "Украинская подборка M3U8", "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlists/playlist_ukraine.m3u8"),
        Source("iptv-org — украинский язык", "Украиноязычные каналы", "https://iptv-org.github.io/iptv/languages/ukr.m3u")
    )
    private val executor = Executors.newSingleThreadExecutor()
    private var player: ExoPlayer? = null
    private lateinit var root: LinearLayout
    private lateinit var status: TextView
    private lateinit var channelList: LinearLayout
    private lateinit var playerView: PlayerView
    private var channels: List<Channel> = emptyList()

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = android.graphics.Color.rgb(11, 18, 32)
        window.navigationBarColor = android.graphics.Color.rgb(11, 18, 32)
        player = ExoPlayer.Builder(this).build().also { exo ->
            exo.addListener(object : Player.Listener {
                override fun onPlayerError(error: PlaybackException) {
                    status.text = "Не удалось воспроизвести канал: ${error.errorCodeName}. Проверь доступность потока."
                }
            })
        }
        buildUi()
    }

    private fun buildUi() {
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(16))
            setBackgroundColor(0xFF0B1220.toInt())
        }
        val scroll = ScrollView(this).apply { isFillViewport = true }
        val page = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, 0, dp(20))
        }
        scroll.addView(page, ViewGroup.LayoutParams(-1, -2))
        root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))

        val header = TextView(this).apply {
            text = "📺 IPTV-СИЛА"
            textSize = 26f
            setTextColor(-1)
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(12), 0, dp(18))
        }
        page.addView(header)

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
        }
        actions.addView(actionButton("Источники") { showSources() },
            LinearLayout.LayoutParams(0, dp(56), 1f).apply { marginEnd = dp(6) })
        actions.addView(actionButton("Открыть M3U") { openPlaylist() },
            LinearLayout.LayoutParams(0, dp(56), 1f).apply { marginStart = dp(6) })
        page.addView(actions)

        status = TextView(this).apply {
            text = "Выбери источник или открой свой M3U-плейлист"
            textSize = 15f
            setTextColor(0xFFB8C5D8.toInt())
            setPadding(0, dp(14), 0, dp(14))
        }
        page.addView(status)

        playerView = PlayerView(this).apply {
            player = this@MainActivity.player
            useController = true
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setBackgroundColor(0xFF000000.toInt())
        }
        page.addView(playerView, LinearLayout.LayoutParams(-1, dp(260)))

        val search = EditText(this).apply {
            hint = "Поиск канала"
            textSize = 16f
            setSingleLine(true)
            setTextColor(-1)
            setHintTextColor(0xFF9EABC0.toInt())
            setPadding(dp(12), dp(8), dp(12), dp(8))
        }
        page.addView(search, LinearLayout.LayoutParams(-1, dp(58)))

        channelList = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        page.addView(channelList)

        search.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                renderChannels(s.toString())
            }
            override fun afterTextChanged(s: android.text.Editable?) {}
        })
        setContentView(root)
    }

    private fun actionButton(label: String, click: () -> Unit) = Button(this).apply {
        text = label
        textSize = 15f
        isAllCaps = false
        setTextColor(-1)
        setBackgroundColor(0xFF24639A.toInt())
        setOnClickListener { click() }
    }

    private fun showSources() {
        val items = sources.map { "${it.name}\n${it.description}" }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("🇺🇦 Украинские IPTV-источники")
            .setItems(items) { _, which -> loadUrl(sources[which].url) }
            .setNeutralButton("Проверить все") { _, _ -> checkSources() }
            .setNegativeButton("Закрыть", null)
            .show()
    }

    private fun checkSources() {
        status.text = "Проверяю M3U-источники…"
        executor.execute {
            val report = sources.map { source ->
                try {
                    val text = download(source.url)
                    val count = text.lineSequence().count { it.trimStart().startsWith("#EXTINF", true) }
                    "${source.name}: доступен, каналов: $count"
                } catch (e: Exception) {
                    "${source.name}: ошибка — ${e.message ?: "недоступен"}"
                }
            }.joinToString("\n")
            runOnUiThread { status.text = report }
        }
    }

    private fun openPlaylist() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/x-mpegurl", "application/vnd.apple.mpegurl", "text/plain"))
        }
        startActivityForResult(intent, 41)
    }

    @Deprecated("Use Activity Result API in a follow-up refactor")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 41 && resultCode == Activity.RESULT_OK) data?.data?.let { uri ->
            executor.execute {
                try {
                    val text = contentResolver.openInputStream(uri)!!.bufferedReader().use { it.readText() }
                    runOnUiThread { parseAndShow(text, uri.toString()) }
                } catch (e: Exception) {
                    runOnUiThread { status.text = "Не удалось открыть плейлист: ${e.message}" }
                }
            }
        }
    }

    private fun loadUrl(url: String) {
        status.text = "Загружаю плейлист…"
        executor.execute {
            try {
                val text = download(url)
                runOnUiThread { parseAndShow(text, url) }
            } catch (e: Exception) {
                runOnUiThread { status.text = "Ошибка загрузки: ${e.message}" }
            }
        }
    }

    private fun download(address: String): String {
        val connection = URL(address).openConnection() as HttpURLConnection
        connection.connectTimeout = 15000
        connection.readTimeout = 20000
        connection.setRequestProperty("User-Agent", "IPTV-SILA-Android/1.0")
        return try {
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    private fun parseAndShow(text: String, base: String) {
        val result = mutableListOf<Channel>()
        var name = "Без названия"
        var group = ""
        val pendingHeaders = linkedMapOf<String, String>()
        text.removePrefix("\uFEFF").lineSequence().forEach { raw ->
            val line = raw.trim()
            when {
                line.startsWith("#EXTINF", true) -> {
                    name = line.substringAfterLast(',').trim().ifBlank { "Без названия" }
                    group = Regex("group-title=\"([^\"]*)\"").find(line)?.groupValues?.get(1).orEmpty()
                    pendingHeaders.clear()
                }
                line.startsWith("#EXTVLCOPT:", true) -> {
                    val option = line.substringAfter(':')
                    val key = option.substringBefore('=').trim().lowercase()
                    val value = option.substringAfter('=', "").trim()
                    when (key) {
                        "http-user-agent" -> if (value.isNotBlank()) pendingHeaders["User-Agent"] = value
                        "http-referrer", "http-referer" -> if (value.isNotBlank()) pendingHeaders["Referer"] = value
                    }
                }
                line.isNotBlank() && !line.startsWith("#") -> {
                    try {
                        val resolved = if (line.startsWith("http://", true) || line.startsWith("https://", true)) {
                            line
                        } else {
                            URL(URL(base), line).toString()
                        }
                        result.add(Channel(name, group, resolved, pendingHeaders.toMap()))
                        pendingHeaders.clear()
                    } catch (_: Exception) {
                        // Skip malformed playlist entries instead of crashing the app.
                    }
                }
            }
        }
        channels = result
        status.text = "Загружено каналов: ${channels.size}"
        renderChannels()
    }

    private fun renderChannels(filter: String = "") {
        channelList.removeAllViews()
        val visible = channels.filter {
            it.name.contains(filter, true) || it.group.contains(filter, true)
        }.take(500)
        visible.forEach { channel ->
            val button = Button(this).apply {
                text = if (channel.group.isBlank()) channel.name else "${channel.name}  ·  ${channel.group}"
                textSize = 14f
                isAllCaps = false
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                minHeight = dp(58)
                setPadding(dp(14), dp(8), dp(14), dp(8))
                setTextColor(-1)
                setBackgroundColor(0xFF151F31.toInt())
                setOnClickListener { playChannel(channel) }
            }
            channelList.addView(button, LinearLayout.LayoutParams(-1, dp(64)).apply {
                bottomMargin = dp(5)
            })
        }
        if (visible.isEmpty()) {
            val empty = TextView(this).apply {
                text = if (channels.isEmpty()) "Сначала загрузи IPTV-плейлист" else "Каналы не найдены"
                textSize = 16f
                setTextColor(0xFFB8C5D8.toInt())
                setPadding(dp(8), dp(18), dp(8), dp(18))
            }
            channelList.addView(empty)
        }
    }

    private fun playChannel(channel: Channel) {
        try {
            status.text = "Подключаюсь: ${channel.name}"
            val uri = Uri.parse(channel.url)
            require(uri.scheme == "http" || uri.scheme == "https") { "Неподдерживаемый адрес потока" }
            val exo = player ?: return
            exo.stop()
            exo.clearMediaItems()
            val requestHeaders = linkedMapOf("User-Agent" to "IPTV-SILA-Android/1.0").apply {
                putAll(channel.headers)
            }
            val dataSourceFactory = DefaultHttpDataSource.Factory()
                .setDefaultRequestProperties(requestHeaders)
            val mediaSource = DefaultMediaSourceFactory(dataSourceFactory)
                .createMediaSource(MediaItem.fromUri(uri))
            exo.setMediaSource(mediaSource)
            exo.prepare()
            exo.playWhenReady = true
        } catch (e: Exception) {
            status.text = "Ошибка запуска канала: ${e.message ?: e.javaClass.simpleName}"
        }
    }

    override fun onDestroy() {
        player?.release()
        player = null
        executor.shutdownNow()
        super.onDestroy()
    }
}
