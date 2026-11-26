from __future__ import annotations
import json, re, sys
from pathlib import Path
from urllib.parse import urljoin
from PySide6.QtCore import Qt, QUrl, QTimer
from PySide6.QtGui import QAction, QColor, QPainter, QLinearGradient, QFont
from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QGridLayout, QLabel, QLineEdit, QPushButton, QFileDialog, QTableWidget, QTableWidgetItem,
    QHeaderView, QSplitter, QTabWidget, QMessageBox, QFrame, QStatusBar, QAbstractItemView)
from PySide6.QtMultimedia import QMediaPlayer, QAudioOutput
from PySide6.QtMultimediaWidgets import QVideoWidget
from server_core import IPTVServer
from sources import UkrainianSourcesPanel

APP_DIR = Path(sys.executable).resolve().parent if getattr(sys, "frozen", False) else Path(__file__).resolve().parent
CONFIG = APP_DIR / "config.json"

DARK = """
QMainWindow,QWidget { background:#101827; color:#e8f0fb; font-family:'Segoe UI'; font-size:10pt; }
QLineEdit { background:#1c2a3e; border:1px solid #344761; border-radius:7px; padding:9px; color:white; }
QPushButton { background:#24649a; border:0; border-radius:7px; padding:9px 14px; color:white; font-weight:600; }
QPushButton:hover { background:#347fb9; } QPushButton:disabled { background:#39485b; color:#9ba9b8; }
QTableWidget { background:#172337; alternate-background-color:#1c2a3e; border:1px solid #30425a; gridline-color:#26384f; selection-background-color:#24649a; }
QHeaderView::section { background:#203149; color:#dbeafe; padding:8px; border:0; }
QTabWidget::pane { border:1px solid #30425a; border-radius:8px; }
QTabBar::tab { background:#1b2a40; padding:10px 18px; margin-right:3px; border-top-left-radius:7px; border-top-right-radius:7px; }
QTabBar::tab:selected { background:#24649a; }
QStatusBar { background:#0b1220; color:#a9bbcf; }
"""

def parse_m3u(text: str, base: str = ""):
    rows, pending, group = [], None, "Каналы"
    for raw in text.replace("\ufeff","").splitlines():
        line=raw.strip()
        if line.startswith("#EXTINF"):
            pending = line.split(",",1)[-1].strip() or "Без названия"
            m=re.search(r'group-title="([^"]*)"',line)
            group=m.group(1) if m else "Каналы"
        elif line and not line.startswith("#") and pending:
            rows.append({"name":pending,"group":group,"url":urljoin(base,line)})
            pending=None
    return rows

class CatsPanel(QWidget):
    def __init__(self):
        super().__init__(); self.phase=0
        self.timer=QTimer(self); self.timer.timeout.connect(self.advance); self.timer.start(90)
    def advance(self): self.phase=(self.phase+1)%360; self.update()
    def paintEvent(self,event):
        p=QPainter(self); p.setRenderHint(QPainter.Antialiasing)
        r=self.rect(); t=(self.phase%180)/180
        c1=QColor.fromHsv(int(202+18*t),180,130); c2=QColor.fromHsv(int(188+25*t),190,105)
        g=QLinearGradient(0,0,r.width(),r.height()); g.setColorAt(0,c1); g.setColorAt(1,c2); p.fillRect(r,g)
        p.setPen(Qt.white); p.setFont(QFont("Segoe UI",18,QFont.Bold)); p.drawText(r.adjusted(0,25,0,0),Qt.AlignHCenter|Qt.AlignTop,"КОШАЧИЙ ТВ")
        p.setFont(QFont("Segoe UI Emoji",92)); p.drawText(r.adjusted(0,0,0,-15),Qt.AlignCenter,"🐈")
        drift=int(24*((self.phase%120)/60-1)) if self.phase%120<60 else int(24*(1-(self.phase%120-60)/60))
        p.setFont(QFont("Segoe UI Emoji",34)); p.drawText(r.adjusted(drift,0,0,-35),Qt.AlignHCenter|Qt.AlignBottom,"🐟       🦋       🐟")

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__(); self.setWindowTitle("IPTV-СИЛА — Windows"); self.resize(1180,760)
        self.server=None; self.channels=[]; self.filtered=[]
        self.player=QMediaPlayer(self); self.audio=QAudioOutput(self); self.player.setAudioOutput(self.audio)
        self.video=QVideoWidget(); self.player.setVideoOutput(self.video)
        self._build(); self._load_config()
    def _build(self):
        tabs=QTabWidget(); self.setCentralWidget(tabs)
        tv=QWidget(); root=QVBoxLayout(tv)
        top=QHBoxLayout(); self.source=QLineEdit(); self.source.setPlaceholderText("URL плейлиста M3U или локальный файл")
        browse=QPushButton("Файл…"); browse.clicked.connect(self.choose_file)
        load=QPushButton("Загрузить"); load.clicked.connect(self.load_local_playlist)
        top.addWidget(self.source,1); top.addWidget(browse); top.addWidget(load); root.addLayout(top)
        splitter=QSplitter(Qt.Horizontal)
        left=QWidget(); lv=QVBoxLayout(left); self.search=QLineEdit(); self.search.setPlaceholderText("Поиск канала…"); self.search.textChanged.connect(self.filter_channels); lv.addWidget(self.search)
        self.table=QTableWidget(0,2); self.table.setHorizontalHeaderLabels(["Канал","Категория"]); self.table.horizontalHeader().setSectionResizeMode(0,QHeaderView.Stretch); self.table.horizontalHeader().setSectionResizeMode(1,QHeaderView.ResizeToContents); self.table.setSelectionBehavior(QAbstractItemView.SelectRows); self.table.setEditTriggers(QAbstractItemView.NoEditTriggers); self.table.cellDoubleClicked.connect(self.play_selected); lv.addWidget(self.table)
        right=QWidget(); rv=QVBoxLayout(right); rv.addWidget(self.video,1); self.now=QLabel("Выбери канал и нажми дважды"); self.now.setStyleSheet("font-size:14pt;font-weight:600;padding:8px"); rv.addWidget(self.now)
        controls=QHBoxLayout()
        play=QPushButton("▶ Воспроизвести"); play.clicked.connect(self.play_current)
        stop=QPushButton("■ Стоп"); stop.clicked.connect(self.player.stop)
        self.volume=QLineEdit("70"); self.volume.setMaximumWidth(55); self.volume.editingFinished.connect(self.set_volume)
        controls.addWidget(play); controls.addWidget(stop); controls.addStretch(); controls.addWidget(QLabel("Громкость")); controls.addWidget(self.volume); rv.addLayout(controls)
        splitter.addWidget(left); splitter.addWidget(right); splitter.setSizes([390,720]); root.addWidget(splitter,1)
        tabs.addTab(tv,"📺 IPTV-клиент")
        server_tab=QWidget(); sv=QVBoxLayout(server_tab)
        sv.addWidget(QLabel("Встроенный LAN-сервер IPTV-СИЛА"))
        grid=QGridLayout(); self.port=QLineEdit("8765"); self.playlist_path=QLineEdit(); self.playlist_path.setPlaceholderText("Файл M3U, который сервер отдаёт телефонам")
        pick=QPushButton("Выбрать…"); pick.clicked.connect(self.choose_server_playlist)
        grid.addWidget(QLabel("Порт"),0,0); grid.addWidget(self.port,0,1); grid.addWidget(QLabel("Плейлист сервера"),1,0); grid.addWidget(self.playlist_path,1,1); grid.addWidget(pick,1,2); sv.addLayout(grid)
        buttons=QHBoxLayout(); self.server_button=QPushButton("▶ Запустить сервер"); self.server_button.clicked.connect(self.toggle_server); buttons.addWidget(self.server_button); sv.addLayout(buttons)
        self.server_info=QLabel("Сервер остановлен. После запуска адрес появится здесь."); self.server_info.setWordWrap(True); self.server_info.setStyleSheet("font-size:12pt;padding:15px;background:#1b2a40;border-radius:8px"); sv.addWidget(self.server_info); sv.addStretch()
        tabs.addTab(server_tab,"🖥 Сервер")
        tabs.addTab(UkrainianSourcesPanel(self),"🇺🇦 Украинские источники")
        cats=CatsPanel(); tabs.addTab(cats,"🐈 Кошачий ТВ")
        self.setStatusBar(QStatusBar()); self.statusBar().showMessage("Готово")
        self.audio.setVolume(.7)
    def choose_file(self):
        f,_=QFileDialog.getOpenFileName(self,"Открыть плейлист","","Плейлисты (*.m3u *.m3u8);;Все файлы (*)")
        if f: self.source.setText(f); self.load_local_playlist()
    def choose_server_playlist(self):
        f,_=QFileDialog.getOpenFileName(self,"Плейлист сервера","","Плейлисты (*.m3u *.m3u8);;Все файлы (*)")
        if f: self.playlist_path.setText(f)
    def load_local_playlist(self):
        src=self.source.text().strip()
        if not src: return
        try:
            if src.lower().startswith(("http://","https://")):
                import urllib.request
                with urllib.request.urlopen(src,timeout=20) as res: data=res.read(12*1024*1024).decode("utf-8-sig")
                base=src
            else:
                path=Path(src); data=path.read_text(encoding="utf-8-sig"); base=path.as_uri()
            self.channels=parse_m3u(data,base); self.filter_channels()
            self.statusBar().showMessage(f"Загружено каналов: {len(self.channels)}")
            self._save_config()
        except Exception as e: QMessageBox.critical(self,"Ошибка плейлиста",str(e))
    def filter_channels(self):
        q=self.search.text().casefold() if hasattr(self,"search") else ""
        self.filtered=[c for c in self.channels if q in c["name"].casefold() or q in c["group"].casefold()]
        self.table.setRowCount(len(self.filtered))
        for i,c in enumerate(self.filtered):
            self.table.setItem(i,0,QTableWidgetItem(c["name"])); self.table.setItem(i,1,QTableWidgetItem(c["group"]))
    def play_selected(self,row,col): self.table.selectRow(row); self.play_current()
    def play_current(self):
        row=self.table.currentRow()
        if row<0 or row>=len(self.filtered): return
        c=self.filtered[row]; self.now.setText("Сейчас: "+c["name"]); self.player.setSource(QUrl(c["url"])); self.player.play()
        self.statusBar().showMessage("Воспроизведение: "+c["name"])
    def set_volume(self):
        try: self.audio.setVolume(max(0,min(100,int(self.volume.text())))/100)
        except ValueError: self.volume.setText("70")
    def toggle_server(self):
        if self.server:
            self.server.stop(); self.server=None; self.server_button.setText("▶ Запустить сервер"); self.server_info.setText("Сервер остановлен."); return
        try:
            port=int(self.port.text()); self.server=IPTVServer("0.0.0.0",port,Path(self.playlist_path.text()) if self.playlist_path.text().strip() else None)
            self.server.start(); self.server_button.setText("■ Остановить сервер")
            self.server_info.setText("Сервер запущен!\nНа этом ПК: http://127.0.0.1:%d\nВ локальной сети: http://%s:%d\nПлейлист API: /api/playlist"%(port,self.server.lan_ip,port))
            self.statusBar().showMessage("LAN-сервер работает")
        except Exception as e: self.server=None; QMessageBox.critical(self,"Не удалось запустить сервер",str(e))
    def _load_config(self):
        try:
            d=json.loads(CONFIG.read_text(encoding="utf-8")); self.source.setText(d.get("client_playlist","")); self.playlist_path.setText(d.get("server_playlist","")); self.port.setText(str(d.get("port",8765)))
            if self.source.text(): self.load_local_playlist()
        except Exception: pass
    def _save_config(self):
        try: CONFIG.write_text(json.dumps({"client_playlist":self.source.text(),"server_playlist":self.playlist_path.text(),"port":int(self.port.text())},ensure_ascii=False,indent=2),encoding="utf-8")
        except Exception: pass
    def closeEvent(self,event):
        self.player.stop()
        if self.server: self.server.stop()
        self._save_config(); event.accept()

if __name__=="__main__":
    app=QApplication(sys.argv); app.setStyle("Fusion"); app.setStyleSheet(DARK)
    w=MainWindow(); w.show(); sys.exit(app.exec())
