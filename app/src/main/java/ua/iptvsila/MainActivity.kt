package ua.iptvsila

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.setPadding
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

private data class Channel(val name: String, val group: String, val url: String)
private data class Source(val name: String, val description: String, val url: String)

class MainActivity : AppCompatActivity() {
    private val sources = listOf(
        Source("iptv-org — Украина", "Открытые каналы Украины", "https://iptv-org.github.io/iptv/countries/ua.m3u"),
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = android.graphics.Color.rgb(11,18,32)
        window.navigationBarColor = android.graphics.Color.rgb(11,18,32)
        player = ExoPlayer.Builder(this).build()
        buildUi()
    }

    private fun buildUi() {
        root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(16); setBackgroundColor(0xFF0B1220.toInt()) }
        val scroll = ScrollView(this)
        val page = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        scroll.addView(page)
        root.addView(scroll, ViewGroup.LayoutParams(-1, 0).also { it.height = 0 })
        val header = TextView(this).apply { text = "📺 IPTV-СИЛА"; textSize = 24f; setTextColor(-1); gravity = Gravity.CENTER_VERTICAL; setPadding(0,8,0,16) }
        page.addView(header)
        val actions = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        actions.addView(actionButton("Источники") { showSources() }, LinearLayout.LayoutParams(0, -2, 1f))
        actions.addView(actionButton("Открыть M3U") { openPlaylist() }, LinearLayout.LayoutParams(0, -2, 1f))
        page.addView(actions)
        status = TextView(this).apply { text = "Выбери источник или открой свой M3U-плейлист"; setTextColor(0xFFB8C5D8.toInt()); setPadding(0,12,0,12) }
        page.addView(status)
        playerView = PlayerView(this).apply { player = this@MainActivity.player; useController = true }
        page.addView(playerView, LinearLayout.LayoutParams(-1, 210))
        val search = EditText(this).apply { hint = "Поиск канала"; setTextColor(-1); setHintTextColor(0xFF9EABC0.toInt()) }
        page.addView(search)
        channelList = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        page.addView(channelList)
        search.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { renderChannels(s.toString()) }
            override fun afterTextChanged(s: android.text.Editable?) {}
        })
        root.removeView(scroll)
        root.addView(scroll, ViewGroup.LayoutParams(-1, -1))
        setContentView(root)
    }

    private fun actionButton(label: String, click: () -> Unit) = Button(this).apply {
        text = label; setTextColor(-1); setBackgroundColor(0xFF24639A.toInt()); setOnClickListener { click() }
    }

    private fun showSources() {
        val items = sources.map { "${it.name}\n${it.description}" }.toTypedArray()
        AlertDialog.Builder(this).setTitle("🇺🇦 Украинские IPTV-источники")
            .setItems(items) { _, which -> loadUrl(sources[which].url) }
            .setNeutralButton("Проверить все") { _, _ -> checkSources() }
            .setNegativeButton("Закрыть", null).show()
    }

    private fun checkSources() {
        status.text = "Проверяю M3U-источники…"
        executor.execute {
            val report = sources.map { source ->
                try {
                    val text = download(source.url)
                    val count = text.lineSequence().count { it.trimStart().startsWith("#EXTINF", true) }
                    "${source.name}: доступен, каналов: $count"
                } catch (e: Exception) { "${source.name}: ошибка — ${e.message ?: "недоступен"}" }
            }.joinToString("\n")
            runOnUiThread { status.text = report }
        }
    }

    private fun openPlaylist() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE); type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/x-mpegurl", "application/vnd.apple.mpegurl", "text/plain"))
        }
        startActivityForResult(intent, 41)
    }

    @Deprecated("Use Activity Result API in a follow-up refactor")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 41 && resultCode == Activity.RESULT_OK) data?.data?.let { uri ->
            executor.execute {
                try { val text = contentResolver.openInputStream(uri)!!.bufferedReader().use { it.readText() }; runOnUiThread { parseAndShow(text, uri.toString()) } }
                catch (e: Exception) { runOnUiThread { status.text = "Не удалось открыть плейлист: ${e.message}" } }
            }
        }
    }

    private fun loadUrl(url: String) {
        status.text = "Загружаю плейлист…"
        executor.execute {
            try { val text = download(url); runOnUiThread { parseAndShow(text, url) } }
            catch (e: Exception) { runOnUiThread { status.text = "Ошибка загрузки: ${e.message}" } }
        }
    }

    private fun download(address: String): String {
        val connection = URL(address).openConnection() as HttpURLConnection
        connection.connectTimeout = 15000; connection.readTimeout = 20000
        connection.setRequestProperty("User-Agent", "IPTV-SILA-Android/1.0")
        return connection.inputStream.bufferedReader().use { it.readText() }.also { connection.disconnect() }
    }

    private fun parseAndShow(text: String, base: String) {
        val result = mutableListOf<Channel>()
        var name = "Без названия"; var group = ""
        text.lineSequence().forEach { raw ->
            val line = raw.trim()
            when {
                line.startsWith("#EXTINF", true) -> {
                    name = line.substringAfterLast(',').trim().ifBlank { "Без названия" }
                    group = Regex("group-title=\"([^\"]*)\"").find(line)?.groupValues?.get(1).orEmpty()
                }
                line.isNotBlank() && !line.startsWith("#") -> {
                    try { result.add(Channel(name, group, URL(URL(base), line).toString())) } catch (_: Exception) {}
                }
            }
        }
        channels = result
        status.text = "Загружено каналов: ${channels.size}"
        renderChannels()
    }

    private fun renderChannels(filter: String = "") {
        channelList.removeAllViews()
        channels.filter { it.name.contains(filter, true) || it.group.contains(filter, true) }.take(500).forEach { channel ->
            val button = Button(this).apply {
                text = if (channel.group.isBlank()) channel.name else "${channel.name}  ·  ${channel.group}"
                isAllCaps = false; gravity = Gravity.START or Gravity.CENTER_VERTICAL
                setTextColor(-1); setBackgroundColor(0xFF151F31.toInt())
                setOnClickListener {
                    player?.setMediaItem(MediaItem.fromUri(channel.url)); player?.prepare(); player?.play()
                    status.text = "Сейчас играет: ${channel.name}"
                }
            }
            channelList.addView(button, LinearLayout.LayoutParams(-1, -2))
        }
    }

    override fun onDestroy() {
        player?.release(); player = null; executor.shutdownNow()
        super.onDestroy()
    }
}
