import UIKit
import AVFoundation
import AVKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = IPTVViewController()
        window?.makeKeyAndVisible()
        return true
    }
}

private struct IPTVSource {
    let name: String
    let detail: String
    let url: URL
}

private struct Channel {
    let name: String
    let group: String
    let url: URL
}

final class IPTVViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private let navy = UIColor(red: 11/255, green: 18/255, blue: 32/255, alpha: 1)
    private let panel = UIColor(red: 21/255, green: 31/255, blue: 49/255, alpha: 1)
    private let blue = UIColor(red: 99/255, green: 179/255, blue: 255/255, alpha: 1)
    private var channels: [Channel] = []
    private var filtered: [Channel] = []
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerItemObservation: NSKeyValueObservation?
    private var catsPlayer: AVQueuePlayer?
    private var catsLooper: AVPlayerLooper?
    private var catsItemObservation: NSKeyValueObservation?
    private var catsLayer: AVPlayerLayer?
    private weak var catsVideoContainerReference: UIView?
    private weak var catVideoStatusReference: UILabel?
    private var currentTab = 0
    private let sources: [IPTVSource] = [
        IPTVSource(name: "iptv-org — Украина", detail: "Открытые каналы Украины", url: URL(string: "https://iptv-org.github.io/iptv/countries/ua.m3u")!),
        IPTVSource(name: "IPTV Nexus — Украина", detail: "181 украинский канал, автоматически обновляемый список", url: URL(string: "https://dearbulut.github.io/iptv/playlists/country/ua.m3u")!),
        IPTVSource(name: "Free-TV — Украина", detail: "Украинская подборка M3U8", url: URL(string: "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlists/playlist_ukraine.m3u8")!),
        IPTVSource(name: "iptv-org — украинский язык", detail: "Украиноязычные каналы из разных стран", url: URL(string: "https://iptv-org.github.io/iptv/languages/ukr.m3u")!)
    ]

    private let serverField = UITextField()
    private let searchField = UITextField()
    private let statusLabel = UILabel()
    private let channelTable = UITableView()
    private let videoContainer = UIView()
    private let nowPlaying = UILabel()
    private let content = UIView()
    private let catsView = UIView()
    private let sourcesView = UIView()
    private let sourcesTable = UITableView()
    private let sourcesStatus = UILabel()
    private let customSourceField = UITextField()
    private let scrollView = UIScrollView()
    private var tabs: UISegmentedControl!
    private let videoPlaceholder = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = navy
        title = "📺 IPTV-СИЛА"
        navigationController?.navigationBar.barTintColor = navy
        navigationController?.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
        buildInterface()
        let saved = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        serverField.text = saved
        if let lastURL = UserDefaults.standard.string(forKey: "lastPlaylistURL"),
           let url = URL(string: lastURL) {
            let lastTitle = UserDefaults.standard.string(forKey: "lastPlaylistTitle") ?? "Последний источник"
            sourcesStatus.text = "Последний источник: \(lastTitle)"
            loadPlaylist(from: url, title: lastTitle, status: sourcesStatus)
        } else if !saved.isEmpty {
            loadPlaylist()
        }
        catsPlayer?.play()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = videoContainer.bounds
        catsLayer?.frame = catsVideoContainerReference?.bounds ?? .zero
    }

    private func style(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.backgroundColor = UIColor(red: 12/255, green: 21/255, blue: 36/255, alpha: 1)
        field.textColor = .white
        field.tintColor = blue
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.heightAnchor.constraint(equalToConstant: 42).isActive = true
    }

    private func buildInterface() {
        let root = UIStackView()
        root.axis = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            root.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])

        tabs = UISegmentedControl(items: ["ТВ", "🇺🇦 Источники", "🐈 Кошачий ТВ"])
        tabs.selectedSegmentIndex = 0
        tabs.addTarget(self, action: #selector(changeTab(_:)), for: .valueChanged)
        root.addArrangedSubview(tabs)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(scrollView)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        style(searchField, placeholder: "Поиск канала…")
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        stack.addArrangedSubview(searchField)

        statusLabel.text = "Укажи адрес IPTV-СИЛА сервера"
        statusLabel.textColor = .lightGray
        statusLabel.font = .systemFont(ofSize: 13)
        stack.addArrangedSubview(statusLabel)

        channelTable.dataSource = self
        channelTable.delegate = self
        channelTable.backgroundColor = panel
        channelTable.separatorColor = UIColor.darkGray
        channelTable.rowHeight = 54
        channelTable.layer.cornerRadius = 12
        channelTable.heightAnchor.constraint(equalToConstant: 260).isActive = true
        stack.addArrangedSubview(channelTable)

        videoContainer.backgroundColor = .black
        videoContainer.layer.cornerRadius = 12
        videoContainer.layer.borderWidth = 1
        videoContainer.layer.borderColor = UIColor(white: 0.35, alpha: 1).cgColor
        videoContainer.clipsToBounds = true
        videoContainer.heightAnchor.constraint(equalToConstant: 190).isActive = true
        videoPlaceholder.text = "▶  Здесь будет видео канала"
        videoPlaceholder.textColor = UIColor(white: 0.72, alpha: 1)
        videoPlaceholder.textAlignment = .center
        videoPlaceholder.font = .systemFont(ofSize: 15, weight: .medium)
        videoPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.addSubview(videoPlaceholder)
        NSLayoutConstraint.activate([
            videoPlaceholder.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor, constant: 8),
            videoPlaceholder.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor, constant: -8),
            videoPlaceholder.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor)
        ])
        let channelFullscreen = UIButton(type: .system)
        channelFullscreen.setTitle("⛶", for: .normal)
        channelFullscreen.setTitleColor(.white, for: .normal)
        channelFullscreen.titleLabel?.font = .systemFont(ofSize: 25, weight: .bold)
        channelFullscreen.backgroundColor = UIColor(white: 0.08, alpha: 0.8)
        channelFullscreen.layer.cornerRadius = 8
        channelFullscreen.translatesAutoresizingMaskIntoConstraints = false
        channelFullscreen.addTarget(self, action: #selector(showChannelFullscreen), for: .touchUpInside)
        videoContainer.addSubview(channelFullscreen)
        NSLayoutConstraint.activate([
            channelFullscreen.widthAnchor.constraint(equalToConstant: 42),
            channelFullscreen.heightAnchor.constraint(equalToConstant: 38),
            channelFullscreen.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor, constant: -8),
            channelFullscreen.topAnchor.constraint(equalTo: videoContainer.topAnchor, constant: 8)
        ])
        stack.addArrangedSubview(videoContainer)
        nowPlaying.text = "Выбери канал"
        nowPlaying.textColor = .white
        nowPlaying.font = .boldSystemFont(ofSize: 18)
        stack.addArrangedSubview(nowPlaying)

        catsView.backgroundColor = UIColor(red: 7/255, green: 20/255, blue: 38/255, alpha: 1)
        catsView.layer.cornerRadius = 18
        catsView.clipsToBounds = true
        catsView.heightAnchor.constraint(equalToConstant: 330).isActive = true

        let catTitle = UILabel()
        catTitle.text = "КОШАЧИЙ ТВ · ВИДЕО"
        catTitle.textColor = .white
        catTitle.font = .boldSystemFont(ofSize: 22)
        catTitle.textAlignment = .center

        let catVideoContainer = UIView()
        catVideoContainer.backgroundColor = .black
        catVideoContainer.layer.cornerRadius = 12
        catVideoContainer.clipsToBounds = true
        catVideoContainer.translatesAutoresizingMaskIntoConstraints = false
        let catVideoStatus = UILabel()
        catVideoStatus.text = "Загружаю видео с кошками…"
        catVideoStatus.textColor = .white
        catVideoStatus.textAlignment = .center
        catVideoStatus.font = .systemFont(ofSize: 14)
        catVideoStatus.translatesAutoresizingMaskIntoConstraints = false
        catVideoContainer.addSubview(catVideoStatus)
        let catFullscreen = UIButton(type: .system)
        catFullscreen.setTitle("⛶", for: .normal)
        catFullscreen.setTitleColor(.white, for: .normal)
        catFullscreen.titleLabel?.font = .systemFont(ofSize: 25, weight: .bold)
        catFullscreen.backgroundColor = UIColor(white: 0.08, alpha: 0.8)
        catFullscreen.layer.cornerRadius = 8
        catFullscreen.translatesAutoresizingMaskIntoConstraints = false
        catFullscreen.addTarget(self, action: #selector(showCatsFullscreen), for: .touchUpInside)
        catVideoContainer.addSubview(catFullscreen)
        NSLayoutConstraint.activate([
            catFullscreen.widthAnchor.constraint(equalToConstant: 42),
            catFullscreen.heightAnchor.constraint(equalToConstant: 38),
            catFullscreen.trailingAnchor.constraint(equalTo: catVideoContainer.trailingAnchor, constant: -8),
            catFullscreen.topAnchor.constraint(equalTo: catVideoContainer.topAnchor, constant: 8)
        ])
        NSLayoutConstraint.activate([
            catVideoStatus.centerXAnchor.constraint(equalTo: catVideoContainer.centerXAnchor),
            catVideoStatus.centerYAnchor.constraint(equalTo: catVideoContainer.centerYAnchor)
        ])
        let catCredit = UILabel()
        catCredit.text = "Видео: Sora/OpenAI · общественное достояние (Wikimedia Commons)"
        catCredit.textColor = .lightGray
        catCredit.font = .systemFont(ofSize: 11)
        catCredit.textAlignment = .center

        let catStack = UIStackView(arrangedSubviews: [catTitle, catVideoContainer, catCredit])
        catStack.axis = .vertical
        catStack.spacing = 12
        catStack.translatesAutoresizingMaskIntoConstraints = false
        catsView.addSubview(catStack)
        NSLayoutConstraint.activate([
            catStack.leadingAnchor.constraint(equalTo: catsView.leadingAnchor, constant: 12),
            catStack.trailingAnchor.constraint(equalTo: catsView.trailingAnchor, constant: -12),
            catStack.topAnchor.constraint(equalTo: catsView.topAnchor, constant: 16),
            catStack.bottomAnchor.constraint(lessThanOrEqualTo: catsView.bottomAnchor, constant: -16),
            catVideoContainer.heightAnchor.constraint(equalToConstant: 245)
        ])

        if let catVideoURL = Bundle.main.url(forResource: "cat-on-bed", withExtension: "mp4") {
            let catItem = AVPlayerItem(url: catVideoURL)
            catsPlayer = AVQueuePlayer()
            catsPlayer?.isMuted = true
            catsLooper = AVPlayerLooper(player: catsPlayer!, templateItem: catItem)
            catsItemObservation = catItem.observe(\.status, options: [.initial, .new]) { [weak catVideoStatus] item, _ in
                DispatchQueue.main.async {
                    if item.status == .readyToPlay { catVideoStatus?.isHidden = true }
                    else if item.status == .failed { catVideoStatus?.text = "Не удалось открыть локальное видео кошек." }
                }
            }
            catsLayer = AVPlayerLayer(player: catsPlayer)
            catsLayer?.videoGravity = .resizeAspect
            catsLayer?.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            catVideoContainer.layer.addSublayer(catsLayer!)
        } else {
            catVideoStatus.text = "Локальное видео не найдено в приложении."
        }
        catsVideoContainerReference = catVideoContainer
        catVideoStatusReference = catVideoStatus
        catsView.isHidden = true
        stack.addArrangedSubview(catsView)

        sourcesView.backgroundColor = panel
        sourcesView.layer.cornerRadius = 14
        sourcesView.isHidden = true
        let sourceTitle = UILabel()
        sourceTitle.text = "🇺🇦 Украинские IPTV-источники"
        sourceTitle.textColor = .white
        sourceTitle.font = .boldSystemFont(ofSize: 20)
        let sourceHint = UILabel()
        sourceHint.text = "Проверяется доступность M3U и число каналов. Это не гарантирует воспроизведение каждого видеопотока."
        sourceHint.textColor = .lightGray
        sourceHint.font = .systemFont(ofSize: 12)
        sourceHint.numberOfLines = 0
        style(serverField, placeholder: "Адрес IPTV-СИЛА сервера, например http://192.168.1.20:8765")
        serverField.keyboardType = .URL
        serverField.delegate = self
        serverField.text = UserDefaults.standard.string(forKey: "serverURL")
        let connect = UIButton(type: .system)
        connect.setTitle("Подключить сервер", for: .normal)
        connect.setTitleColor(.white, for: .normal)
        connect.backgroundColor = UIColor(red: 36/255, green: 99/255, blue: 154/255, alpha: 1)
        connect.layer.cornerRadius = 10
        connect.heightAnchor.constraint(equalToConstant: 42).isActive = true
        connect.addTarget(self, action: #selector(connectServer), for: .touchUpInside)

        style(customSourceField, placeholder: "URL своего M3U/M3U8-плейлиста")
        customSourceField.keyboardType = .URL
        customSourceField.delegate = self
        customSourceField.text = UserDefaults.standard.string(forKey: "customSourceURL")
        let customSourceButton = UIButton(type: .system)
        customSourceButton.setTitle("Добавить / загрузить свой сервер", for: .normal)
        customSourceButton.setTitleColor(.white, for: .normal)
        customSourceButton.backgroundColor = UIColor(red: 36/255, green: 99/255, blue: 154/255, alpha: 1)
        customSourceButton.layer.cornerRadius = 10
        customSourceButton.heightAnchor.constraint(equalToConstant: 42).isActive = true
        customSourceButton.addTarget(self, action: #selector(loadCustomSource), for: .touchUpInside)
        let sourceCheck = UIButton(type: .system)
        sourceCheck.setTitle("Проверить все источники", for: .normal)
        sourceCheck.setTitleColor(.white, for: .normal)
        sourceCheck.backgroundColor = UIColor(red: 36/255, green: 99/255, blue: 154/255, alpha: 1)
        sourceCheck.layer.cornerRadius = 10
        sourceCheck.heightAnchor.constraint(equalToConstant: 42).isActive = true
        sourceCheck.addTarget(self, action: #selector(checkAllSources), for: .touchUpInside)
        sourcesStatus.text = "Выбери источник, чтобы загрузить его каналы."
        sourcesStatus.textColor = .lightGray
        sourcesStatus.font = .systemFont(ofSize: 12)
        sourcesStatus.numberOfLines = 0
        sourcesTable.dataSource = self
        sourcesTable.delegate = self
        sourcesTable.backgroundColor = panel
        sourcesTable.separatorColor = .darkGray
        sourcesTable.rowHeight = 62
        sourcesTable.heightAnchor.constraint(equalToConstant: 260).isActive = true
        let sourceStack = UIStackView(arrangedSubviews: [sourceTitle, sourceHint, serverField, connect, customSourceField, customSourceButton, sourceCheck, sourcesStatus, sourcesTable])
        sourceStack.axis = .vertical
        sourceStack.spacing = 10
        sourceStack.translatesAutoresizingMaskIntoConstraints = false
        sourcesView.addSubview(sourceStack)
        NSLayoutConstraint.activate([
            sourceStack.leadingAnchor.constraint(equalTo: sourcesView.leadingAnchor, constant: 12),
            sourceStack.trailingAnchor.constraint(equalTo: sourcesView.trailingAnchor, constant: -12),
            sourceStack.topAnchor.constraint(equalTo: sourcesView.topAnchor, constant: 12),
            sourceStack.bottomAnchor.constraint(equalTo: sourcesView.bottomAnchor, constant: -12)
        ])
        stack.addArrangedSubview(sourcesView)
    }

    @objc private func changeTab(_ sender: UISegmentedControl) {
        currentTab = sender.selectedSegmentIndex
        let tvHidden = currentTab != 0
        serverField.isHidden = tvHidden
        searchField.isHidden = tvHidden
        statusLabel.isHidden = tvHidden
        channelTable.isHidden = tvHidden
        videoContainer.isHidden = tvHidden
        nowPlaying.isHidden = tvHidden
        sourcesView.isHidden = currentTab != 1
        catsView.isHidden = currentTab != 2
        if currentTab == 2 { catsPlayer?.play() } else { catsPlayer?.pause() }
    }

    @objc private func connectServer() {
        view.endEditing(true)
        guard let raw = serverField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let base = URL(string: raw), base.scheme != nil, base.host != nil else {
            statusLabel.text = "Введи корректный адрес сервера"
            return
        }
        UserDefaults.standard.set(raw, forKey: "serverURL")
        loadPlaylist()
    }

    private func loadPlaylist() {
        guard let raw = serverField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let base = URL(string: raw), let url = URL(string: "/api/playlist", relativeTo: base)?.absoluteURL else { return }
        loadPlaylist(from: url, title: "IPTV-СИЛА сервер", status: sourcesStatus)
    }

    @objc private func showChannelFullscreen() {
        guard let player = player else { return }
        presentFullscreen(player: player)
    }

    @objc private func showCatsFullscreen() {
        guard let player = catsPlayer else { return }
        presentFullscreen(player: player)
    }

    private func presentFullscreen(player: AVPlayer) {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    private func parseM3U(_ text: String, baseURL: URL? = nil) -> [Channel] {
        let lines = text.components(separatedBy: .newlines)
        var result: [Channel] = []
        var name: String?
        var group = "Каналы"
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF") {
                let parts = line.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                name = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : "Без названия"
                if let range = line.range(of: #"group-title="([^"]*)""#, options: .regularExpression) {
                    let value = String(line[range])
                    group = value.replacingOccurrences(of: #"^group-title="|"$"#, with: "", options: .regularExpression)
                } else { group = "Каналы" }
            } else if !line.isEmpty && !line.hasPrefix("#"), let channelName = name, let url = URL(string: line, relativeTo: baseURL)?.absoluteURL {
                result.append(Channel(name: channelName, group: group, url: url))
                name = nil
            }
        }
        return result
    }

    @objc private func searchChanged() {
        let query = (searchField.text ?? "").lowercased()
        filtered = query.isEmpty ? channels : channels.filter { $0.name.lowercased().contains(query) || $0.group.lowercased().contains(query) }
        channelTable.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableView === sourcesTable ? sources.count : filtered.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView === sourcesTable {
            let id = "source"
            let cell = tableView.dequeueReusableCell(withIdentifier: id) ?? UITableViewCell(style: .subtitle, reuseIdentifier: id)
            let source = sources[indexPath.row]
            cell.textLabel?.text = source.name
            cell.textLabel?.textColor = .white
            cell.detailTextLabel?.text = source.detail + " · Нажми для загрузки"
            cell.detailTextLabel?.textColor = .lightGray
            cell.backgroundColor = panel
            return cell
        }
        let id = "channel"
        let cell = tableView.dequeueReusableCell(withIdentifier: id) ?? UITableViewCell(style: .subtitle, reuseIdentifier: id)
        let channel = filtered[indexPath.row]
        cell.textLabel?.text = channel.name
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.text = channel.group
        cell.detailTextLabel?.textColor = .lightGray
        cell.backgroundColor = panel
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView === sourcesTable {
            loadSource(sources[indexPath.row])
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        let channel = filtered[indexPath.row]
        nowPlaying.text = channel.name
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        videoPlaceholder.isHidden = true
        videoContainer.layoutIfNeeded()
        let item = AVPlayerItem(url: channel.url)
        item.preferredForwardBufferDuration = 5
        playerItemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch observedItem.status {
                case .readyToPlay:
                    self.statusLabel.text = "Поток подключён: \(channel.name)"
                    self.player?.play()
                case .failed:
                    self.statusLabel.text = "Ошибка потока: \(observedItem.error?.localizedDescription ?? "неизвестная ошибка")"
                default:
                    self.statusLabel.text = "Подключаю поток: \(channel.name)…"
                }
            }
        }
        player = AVPlayer(playerItem: item)
        player?.automaticallyWaitsToMinimizeStalling = false
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        videoContainer.layoutIfNeeded()
        layer.frame = videoContainer.bounds
        videoContainer.layer.addSublayer(layer)
        playerLayer = layer
        player?.play()
        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func loadSource(_ source: IPTVSource) {
        loadPlaylist(from: source.url, title: source.name, status: sourcesStatus)
    }

    @objc private func loadCustomSource() {
        view.endEditing(true)
        guard let raw = customSourceField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            sourcesStatus.text = "Введи корректный HTTP(S) URL плейлиста M3U/M3U8"
            return
        }
        UserDefaults.standard.set(raw, forKey: "customSourceURL")
        loadPlaylist(from: url, title: "Мой сервер", status: sourcesStatus)
    }

    private func loadPlaylist(from url: URL, title: String, status: UILabel) {
        status.text = "Загружаю \(title)…"
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error { status.text = "Ошибка: \(error.localizedDescription)"; return }
                guard let data = data, let text = String(data: data, encoding: .utf8) else {
                    status.text = "Не удалось прочитать M3U"; return
                }
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    status.text = "HTTP \(http.statusCode)"; return
                }
                let parsed = self.parseM3U(text)
                guard !parsed.isEmpty else { status.text = "Плейлист пустой или не содержит корректных M3U-каналов"; return }
                UserDefaults.standard.set(url.absoluteString, forKey: "lastPlaylistURL")
                UserDefaults.standard.set(title, forKey: "lastPlaylistTitle")
                self.channels = parsed
                self.filtered = parsed
                self.searchField.text = ""
                self.channelTable.reloadData()
                self.statusLabel.text = "Каналов: \(self.channels.count) · \(title)"
                status.text = "Загружено каналов: \(self.channels.count). Перехожу к ТВ…"
                self.tabs.selectedSegmentIndex = 0
                self.changeTab(self.tabs)
            }
        }.resume()
    }

    @objc private func checkAllSources() {
        sourcesStatus.text = "Проверяю источники…"
        let group = DispatchGroup()
        var results: [String] = []
        let lock = NSLock()
        for source in sources {
            group.enter()
            URLSession.shared.dataTask(with: source.url) { data, response, error in
                let result: String
                if let error = error { result = "✗ \(source.name): \(error.localizedDescription)" }
                else if let http = response as? HTTPURLResponse, http.statusCode >= 400 { result = "✗ \(source.name): HTTP \(http.statusCode)" }
                else if let data = data, let text = String(data: data, encoding: .utf8), text.contains("#EXTM3U") {
                    let count = text.components(separatedBy: "#EXTINF").count - 1
                    result = "✓ \(source.name): M3U доступен, каналов — \(count)"
                } else { result = "✗ \(source.name): ответ не M3U" }
                lock.lock(); results.append(result); lock.unlock()
                group.leave()
            }.resume()
        }
        group.notify(queue: .main) {
            self.sourcesStatus.text = results.joined(separator: "\n")
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if textField === serverField { connectServer() }
        return true
    }
}
