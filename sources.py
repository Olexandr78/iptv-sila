from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

from PySide6.QtCore import QObject, QRunnable, QThreadPool, Signal
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QTableWidget,
    QTableWidgetItem, QHeaderView, QMessageBox
)

SOURCES = [
    {
        "name": "iptv-org — Украина",
        "kind": "Страна · открытые потоки",
        "url": "https://iptv-org.github.io/iptv/countries/ua.m3u",
        "note": "Каталог каналов Украины; ссылки обновляются проектом iptv-org.",
    },
    {
        "name": "Free-TV — Украина",
        "kind": "Подборка · M3U8",
        "url": "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlists/playlist_ukraine.m3u8",
        "note": "Публичный плейлист; часть потоков может быть ограничена или недоступна.",
    },
    {
        "name": "iptv-org — украинский язык",
        "kind": "Язык · открытые потоки",
        "url": "https://iptv-org.github.io/iptv/languages/ukr.m3u",
        "note": "Украиноязычные каналы из разных стран, не только украинские телеканалы.",
    },
]

def _read_playlist(url: str):
    req = Request(url, headers={"User-Agent": "IPTV-SILA/1.0"})
    with urlopen(req, timeout=15) as response:
        body = response.read(16 * 1024 * 1024).decode("utf-8-sig", errors="replace")
    if "#EXTM3U" not in body[:512]:
        raise ValueError("Ответ не похож на M3U-плейлист")
    count = sum(1 for line in body.splitlines() if line.strip().startswith("#EXTINF"))
    return count

class _Signals(QObject):
    done = Signal(int, bool, str)

class _CheckTask(QRunnable):
    def __init__(self, index: int, url: str):
        super().__init__()
        self.index = index
        self.url = url
        self.signals = _Signals()

    def run(self):
        try:
            count = _read_playlist(self.url)
            self.signals.done.emit(self.index, True, f"Доступен · записей каналов: {count}")
        except Exception as exc:
            self.signals.done.emit(self.index, False, f"Недоступен: {exc}")

class UkrainianSourcesPanel(QWidget):
    def __init__(self, main_window):
        super().__init__()
        self.main_window = main_window
        self.pool = QThreadPool.globalInstance()
        self.tasks = []
        layout = QVBoxLayout(self)
        intro = QLabel(
            "Публичные украинские IPTV-источники. Проверка проверяет загрузку самого M3U, "
            "а не гарантирует воспроизведение каждого телеканала."
        )
        intro.setWordWrap(True)
        layout.addWidget(intro)

        self.table = QTableWidget(len(SOURCES), 4)
        self.table.setHorizontalHeaderLabels(["Источник", "Тип", "Плейлист", "Состояние"])
        self.table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeToContents)
        self.table.horizontalHeader().setSectionResizeMode(2, QHeaderView.Stretch)
        self.table.horizontalHeader().setSectionResizeMode(3, QHeaderView.Stretch)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.setSelectionBehavior(QTableWidget.SelectRows)
        layout.addWidget(self.table, 1)

        for i, source in enumerate(SOURCES):
            self.table.setItem(i, 0, QTableWidgetItem(source["name"]))
            self.table.setItem(i, 1, QTableWidgetItem(source["kind"]))
            self.table.setItem(i, 2, QTableWidgetItem(source["url"]))
            self.table.setItem(i, 3, QTableWidgetItem("Не проверен"))

        buttons = QHBoxLayout()
        self.check_button = QPushButton("Проверить все источники")
        self.check_button.clicked.connect(self.check_all)
        self.load_button = QPushButton("Загрузить выбранный плейлист в IPTV-клиент")
        self.load_button.clicked.connect(self.load_selected)
        buttons.addWidget(self.check_button)
        buttons.addWidget(self.load_button)
        layout.addLayout(buttons)

        self.details = QLabel(
            "В каталоге только прямые публичные ссылки на плейлисты. Платные сервисы и "
            "закрытые потоки не включены. Доступность отдельных каналов зависит от вещателя, "
            "региона и текущего состояния потока."
        )
        self.details.setWordWrap(True)
        self.details.setStyleSheet("padding:10px;background:#1b2a40;border-radius:8px")
        layout.addWidget(self.details)

    def check_all(self):
        self.check_button.setEnabled(False)
        self.tasks.clear()
        for i, source in enumerate(SOURCES):
            self.table.setItem(i, 3, QTableWidgetItem("Проверяется…"))
            task = _CheckTask(i, source["url"])
            task.signals.done.connect(self._on_result)
            self.tasks.append(task)
            self.pool.start(task)

    def _on_result(self, index: int, ok: bool, message: str):
        self.table.setItem(index, 3, QTableWidgetItem(("✓ " if ok else "✗ ") + message))
        if all(
            self.table.item(i, 3) and self.table.item(i, 3).text() != "Проверяется…"
            for i in range(len(SOURCES))
        ):
            self.check_button.setEnabled(True)

    def load_selected(self):
        row = self.table.currentRow()
        if row < 0:
            QMessageBox.information(self, "IPTV-СИЛА", "Выбери источник в списке.")
            return
        url = SOURCES[row]["url"]
        self.main_window.source.setText(url)
        self.main_window.load_local_playlist()
