/* HostsEditor 主页脚本：三语、三主题、会打字的 hosts 编辑器演示、滚动渐入、动态下载直链 */
(function () {
  'use strict';

  var doc = document.documentElement;
  doc.classList.add('js');
  var KEY_LANG = 'hostseditor.lang';
  var KEY_THEME = 'hostseditor.theme';
  var params = new URLSearchParams(location.search);
  var reduceMQ = matchMedia('(prefers-reduced-motion: reduce)');
  var darkMQ = matchMedia('(prefers-color-scheme: dark)');

  function store(key, value) {
    try {
      localStorage.setItem(key, value);
    } catch (e) {
      // 隐私模式下写入失败时忽略
    }
  }
  function load(key) {
    try {
      return localStorage.getItem(key);
    } catch (e) {
      return null;
    }
  }

  /* ---------------- 文案 ---------------- */
  var T = {
    'zh-Hans': {
      'meta.title': 'HostsEditor — macOS hosts 文件编辑与方案切换工具',
      'meta.desc': 'HostsEditor 是 macOS 上的 hosts 文件编辑与方案切换工具：多方案管理、远程方案、菜单栏快速切换，通过特权 Helper 安全写回 /etc/hosts 并自动刷新 DNS 缓存。',
      'a11y.skip': '跳到正文', 'a11y.home': 'HostsEditor 首页', 'a11y.nav': '页面导航', 'a11y.lang': '切换语言', 'a11y.theme': '主题',
      'a11y.github': 'GitHub 仓库', 'a11y.footer': '页脚链接', 'a11y.icon': 'HostsEditor 图标',
      'theme.light': '浅色', 'theme.dark': '深色', 'theme.system': '跟随系统',
      'nav.features': '功能', 'nav.how': '工作方式', 'nav.keys': '快捷键', 'nav.faq': '常见问题', 'nav.download': '下载',
      'hero.eyebrow': '# macOS 上的 hosts 编辑与方案切换工具',
      'hero.title': '勾选方案，<span class="grad">hosts 即刻切换</span>',
      'hero.lead': '为开发、测试、预发、线上环境各存一套 hosts。勾选即启用，多个方案组合后经特权 Helper 写回 <code>/etc/hosts</code>，写入后自动刷新 DNS 缓存。',
      'hero.req': 'macOS 13.0+ · Apple 公证 · Sparkle 自动更新',
      'dl.arm': 'Apple 芯片版', 'dl.intel': 'Intel 版', 'dl.latest': '最新版本',
      'demo.sidebar': '方案列表', 'demo.system': '系统', 'demo.default': '默认', 'demo.local': '本地配置', 'demo.remote': '远程配置',
      'demo.hint': '↑ 勾选左侧方案，/etc/hosts 实时变化；点名称查看单个方案',
      'demo.on': '{n} 个方案已启用', 'demo.readonly': '只读', 'demo.typing': '编辑中…',
      'demo.saved': '✓ 已写入 /etc/hosts · DNS 缓存已刷新', 'demo.toggle': '启用「{name}」',
      'p.dev': '开发环境', 'p.staging': '预发环境', 'p.adblock': '屏蔽广告',
      'c.dev': '# 本地开发服务', 'c.staging': '# 预发环境服务器', 'c.adblock': '# 屏蔽广告与统计域名', 'c.team': '# 团队共享配置',
      'c.remote': '# 来源：https://hosts.example.com/team.txt',
      'features.k': 'features', 'features.title': '把 hosts 当成一组可开关的方案来管理', 'features.sub': '每一项都来自应用的实际功能。',
      'f1.t': '多方案管理', 'f1.d': '创建多套本地 hosts 方案，按需启用、停用、复制或删除；多个启用方案组合后一起写入。',
      'f2.t': '系统级应用', 'f2.d': '组合内容写入系统 /etc/hosts，写入后自动刷新 DNS 缓存，修改立即生效。',
      'f3.t': '远程方案', 'f3.d': '从 http / https 地址拉取 hosts 保存为方案，可手动刷新，也可每小时、每 6 小时或每天自动刷新。',
      'f4.t': '自动备份', 'f4.d': '每次写入前备份旧内容，保留最近 30 份，可从「文件」菜单在访达中查看。',
      'f5.t': '菜单栏快速切换', 'f5.d': '状态栏图标列出全部方案，点一下即可启用或关闭，不必打开主窗口。',
      'f6.t': '为 hosts 定制的编辑器', 'f6.d': '注释、IP（含 IPv6）、主机名语法高亮，查找替换、⌘/ 批量注释，支持浅色和深色外观。',
      'f7.t': '导入与导出', 'f7.d': '把本地 hosts 文件导入为方案，或把当前内容导出为文本文件。',
      'f8.t': '保留原始内容', 'f8.d': '只改写自己的管理块；写入前重新读取系统 hosts，其他工具写入的内容原样保留。',
      'f9.t': '防误操作', 'f9.d': '有未保存的修改时窗口关闭按钮显示提示点，退出前二次确认。',
      'features.also': '# 另有：简体中文 / 繁體中文 / English 界面；Sparkle 按芯片架构分别推送更新',
      'how.k': 'how-it-works', 'how.title': '只改写自己管理的那几段', 'how.sub': '每个启用的方案写成一个带标记的块，块外的内容原样保留。',
      'term.system.k': '系统', 'term.system.v': '当前 /etc/hosts 的完整内容，可直接编辑并保存。',
      'term.default.k': '默认', 'term.default.v': '剥离 HostsEditor 管理块后的基础内容，只读查看。',
      'term.local.k': '本地配置', 'term.local.v': '手动维护的方案，可编辑、启用、删除。',
      'term.remote.k': '远程配置', 'term.remote.v': '从 URL 拉取的方案，支持刷新。',
      'how.term': '写入流程（示意）',
      'log.1': '重新读取 /etc/hosts，保留外部改动', 'log.2': '组合基础内容与已启用方案', 'log.3': '备份旧内容（保留最近 30 份）',
      'log.5': 'Helper 写入 /etc/hosts', 'log.8': '回读校验写入结果', 'log.9': '已生效',
      'sec.1': '主应用负责界面、方案管理、状态栏和远程拉取，本身以普通用户权限运行。',
      'sec.2': 'Helper 通过 SMAppService 注册为后台守护进程，主应用经 XPC 与它通信。',
      'sec.3': '首次安装或重新注册 Helper 时需要系统授权。',
      'shot.k': 'screenshot', 'shot.title': '应用里的样子', 'shot.sub': '左侧是方案列表，勾选即启用；右侧是带语法高亮的编辑器。',
      'shot.alt': 'HostsEditor 主界面：左侧方案列表，右侧语法高亮的 hosts 编辑器',
      'keys.k': 'keybindings', 'keys.title': '常用快捷键',
      'k1': '新建本地方案 / 新建远程方案', 'k2': '导入 hosts 文件为本地方案', 'k3': '保存并应用', 'k4': '导出当前内容',
      'k5': '查找 / 替换', 'k6': '注释或取消注释选中行', 'k7': '调整编辑器字号',
      'faq.k': 'getting-started', 'faq.title': '首次使用与常见问题',
      's1': '下载与芯片匹配的 DMG，把 HostsEditor 拖进「应用程序」后打开。',
      's2': '首次读取或写入系统 hosts 时，应用会注册特权 Helper。',
      's3': '系统要求授权时，输入管理员密码。',
      's4': '若提示「需要允许后台程序」，前往「系统设置 › 通用 › 登录项与扩展程序」允许 HostsEditor 的后台程序，然后重新打开应用。',
      'q1.q': '出现 “couldn’t communicate with a helper application”',
      'q1.a1': '通常是系统里残留了旧版本的后台任务记录。先退出 HostsEditor，再在终端清理旧记录：',
      'q1.a2': '确认 /Applications 与 ~/Applications 里只有一份 HostsEditor.app，重新打开应用，点一次「启用或修复后台帮助程序」，再触发一次系统 hosts 的读取或写入。',
      'q2.q': '提示「需要允许后台程序」', 'q2.a': '前往「系统设置 › 通用 › 登录项与扩展程序」，允许 HostsEditor 的后台程序，然后重新启动应用。',
      'q3.q': '确认自己的 Mac 是哪种芯片', 'q3.a': '打开「苹果菜单 › 关于本机」，看「芯片」或「处理器」一栏：显示 Apple M 系列选 Apple 芯片版，显示 Intel 选 Intel 版。',
      'copy': '复制', 'copied': '已复制',
      'dl.title': '下载 HostsEditor',
      'dl.sub': '需要 macOS 13.0 或更高版本。安装包已通过 Apple 公证，打开 DMG 后把应用拖进「应用程序」即可；内置 Sparkle 自动更新，只推送与本机芯片匹配的版本。',
      'dl.all': '全部版本与更新说明 →',
      'foot.more': 'VanJay 的更多作品', 'foot.issues': '反馈问题'
    },
    'en': {
      'meta.title': 'HostsEditor — hosts file editor and profile switcher for macOS',
      'meta.desc': 'HostsEditor edits and switches hosts profiles on macOS: multiple profiles, remote profiles, menu bar switching, and safe writes to /etc/hosts through a privileged helper with automatic DNS cache flush.',
      'a11y.skip': 'Skip to content', 'a11y.home': 'HostsEditor home', 'a11y.nav': 'Page navigation', 'a11y.lang': 'Language', 'a11y.theme': 'Theme',
      'a11y.github': 'GitHub repository', 'a11y.footer': 'Footer links', 'a11y.icon': 'HostsEditor icon',
      'theme.light': 'Light', 'theme.dark': 'Dark', 'theme.system': 'Match system',
      'nav.features': 'Features', 'nav.how': 'How it works', 'nav.keys': 'Shortcuts', 'nav.faq': 'FAQ', 'nav.download': 'Download',
      'hero.eyebrow': '# hosts editor and profile switcher for macOS',
      'hero.title': 'Tick a profile.<br><span class="grad">Your hosts switch instantly.</span>',
      'hero.lead': 'Keep one hosts profile for each environment — dev, test, staging, production. Tick to enable; enabled profiles are combined and written to <code>/etc/hosts</code> by a privileged helper, then the DNS cache is flushed.',
      'hero.req': 'macOS 13.0+ · Notarized by Apple · Sparkle updates',
      'dl.arm': 'Apple silicon', 'dl.intel': 'Intel', 'dl.latest': 'latest',
      'demo.sidebar': 'Profiles', 'demo.system': 'System', 'demo.default': 'Default', 'demo.local': 'Local Profiles', 'demo.remote': 'Remote Profiles',
      'demo.hint': '↑ Tick a profile and /etc/hosts updates live; click a name to view that profile',
      'demo.on': '{n} enabled', 'demo.readonly': 'read-only', 'demo.typing': 'editing…',
      'demo.saved': '✓ Written to /etc/hosts · DNS cache flushed', 'demo.toggle': 'Enable “{name}”',
      'p.dev': 'Development', 'p.staging': 'Staging', 'p.adblock': 'Block Ads',
      'c.dev': '# local dev services', 'c.staging': '# staging servers', 'c.adblock': '# ad and analytics domains', 'c.team': '# shared by the team',
      'c.remote': '# source: https://hosts.example.com/team.txt',
      'features.k': 'features', 'features.title': 'Manage hosts as profiles you can switch on and off', 'features.sub': 'Every item below is a feature of the app.',
      'f1.t': 'Multiple profiles', 'f1.d': 'Create local hosts profiles, then enable, disable, duplicate or delete them. All enabled profiles are written together.',
      'f2.t': 'System-wide apply', 'f2.d': 'The combined content is written to /etc/hosts and the DNS cache is flushed, so changes take effect right away.',
      'f3.t': 'Remote profiles', 'f3.d': 'Fetch hosts from an http / https URL as a profile. Refresh by hand, or automatically every hour, 6 hours or day.',
      'f4.t': 'Automatic backups', 'f4.d': 'The previous content is backed up before every write. The latest 30 are kept and can be shown in Finder from the File menu.',
      'f5.t': 'Menu bar switching', 'f5.d': 'The status bar icon lists every profile; one click turns a profile on or off without opening the main window.',
      'f6.t': 'An editor built for hosts', 'f6.d': 'Highlighting for comments, IPs (including IPv6) and hostnames, find and replace, ⌘/ to toggle comments, light and dark appearance.',
      'f7.t': 'Import and export', 'f7.d': 'Import local hosts files as profiles, or export the current content as a text file.',
      'f8.t': 'Original content kept', 'f8.d': 'Only its own managed blocks are rewritten. /etc/hosts is re-read before every write, so edits made by other tools stay intact.',
      'f9.t': 'Guards against mistakes', 'f9.d': 'The close button shows a dot while there are unsaved edits, and quitting asks for confirmation.',
      'features.also': '# Also: Simplified Chinese / Traditional Chinese / English UI; Sparkle delivers updates per CPU architecture',
      'how.k': 'how-it-works', 'how.title': 'Only its own blocks get rewritten', 'how.sub': 'Each enabled profile becomes a marked block. Everything outside the blocks stays as it is.',
      'term.system.k': 'System', 'term.system.v': 'The full current /etc/hosts. Edit and save it directly.',
      'term.default.k': 'Default', 'term.default.v': 'The base content with HostsEditor blocks stripped. Read-only.',
      'term.local.k': 'Local', 'term.local.v': 'Profiles you maintain by hand: edit, enable, delete.',
      'term.remote.k': 'Remote', 'term.remote.v': 'Profiles fetched from a URL, with refresh support.',
      'how.term': 'Write flow (illustration)',
      'log.1': 're-read /etc/hosts, keep outside edits', 'log.2': 'combine base content and enabled profiles', 'log.3': 'back up the old content (latest 30 kept)',
      'log.5': 'helper writes /etc/hosts', 'log.8': 'read back and verify', 'log.9': 'in effect',
      'sec.1': 'The app handles the UI, profiles, status bar and remote fetching, and runs with normal user rights.',
      'sec.2': 'The helper is registered as a background daemon via SMAppService; the app talks to it over XPC.',
      'sec.3': 'Installing or re-registering the helper asks for system authorization.',
      'shot.k': 'screenshot', 'shot.title': 'What it looks like', 'shot.sub': 'Profiles on the left — tick to enable. A syntax-highlighting editor on the right.',
      'shot.alt': 'HostsEditor main window: profile list on the left, syntax-highlighted hosts editor on the right',
      'keys.k': 'keybindings', 'keys.title': 'Keyboard shortcuts',
      'k1': 'New local profile / new remote profile', 'k2': 'Import a hosts file as a local profile', 'k3': 'Save and apply', 'k4': 'Export current content',
      'k5': 'Find / replace', 'k6': 'Comment or uncomment selected lines', 'k7': 'Change editor font size',
      'faq.k': 'getting-started', 'faq.title': 'Getting started and FAQ',
      's1': 'Download the DMG for your chip, drag HostsEditor into Applications and open it.',
      's2': 'The first time it reads or writes the system hosts file, the app registers its privileged helper.',
      's3': 'Enter an administrator password when macOS asks for authorization.',
      's4': 'If you see “background item needs approval”, go to System Settings › General › Login Items & Extensions, allow HostsEditor, then reopen the app.',
      'q1.q': '“couldn’t communicate with a helper application”',
      'q1.a1': 'Usually an old background task record is left in the system. Quit HostsEditor and clear the old records in Terminal:',
      'q1.a2': 'Make sure there is only one HostsEditor.app across /Applications and ~/Applications, reopen the app, click “Enable or Repair Helper” once, then read or write the system hosts again.',
      'q2.q': '“background item needs approval”', 'q2.a': 'Go to System Settings › General › Login Items & Extensions, allow the HostsEditor background item, then restart the app.',
      'q3.q': 'Which chip does my Mac have?', 'q3.a': 'Open Apple menu › About This Mac and look at “Chip” or “Processor”: Apple M-series means the Apple silicon build, Intel means the Intel build.',
      'copy': 'Copy', 'copied': 'Copied',
      'dl.title': 'Download HostsEditor',
      'dl.sub': 'Requires macOS 13.0 or later. Both builds are notarized by Apple: open the DMG and drag the app into Applications. Sparkle updates deliver only the build that matches your chip.',
      'dl.all': 'All versions and release notes →',
      'foot.more': 'More apps by VanJay', 'foot.issues': 'Report an issue'
    },
    'zh-Hant': {
      'meta.title': 'HostsEditor — macOS hosts 檔案編輯與方案切換工具',
      'meta.desc': 'HostsEditor 是 macOS 上的 hosts 檔案編輯與方案切換工具：多方案管理、遠端方案、選單列快速切換，透過特權輔助程式安全寫回 /etc/hosts 並自動清除 DNS 快取。',
      'a11y.skip': '跳到內文', 'a11y.home': 'HostsEditor 首頁', 'a11y.nav': '頁面導覽', 'a11y.lang': '切換語言', 'a11y.theme': '主題',
      'a11y.github': 'GitHub 儲存庫', 'a11y.footer': '頁尾連結', 'a11y.icon': 'HostsEditor 圖示',
      'theme.light': '淺色', 'theme.dark': '深色', 'theme.system': '跟隨系統',
      'nav.features': '功能', 'nav.how': '運作方式', 'nav.keys': '快速鍵', 'nav.faq': '常見問題', 'nav.download': '下載',
      'hero.eyebrow': '# macOS 上的 hosts 編輯與方案切換工具',
      'hero.title': '勾選方案，<span class="grad">hosts 立即切換</span>',
      'hero.lead': '為開發、測試、預發、正式環境各存一套 hosts。勾選即啟用，多個方案組合後由特權輔助程式寫回 <code>/etc/hosts</code>，寫入後自動清除 DNS 快取。',
      'hero.req': 'macOS 13.0+ · Apple 公證 · Sparkle 自動更新',
      'dl.arm': 'Apple 晶片版', 'dl.intel': 'Intel 版', 'dl.latest': '最新版本',
      'demo.sidebar': '方案列表', 'demo.system': '系統', 'demo.default': '預設', 'demo.local': '本地設定', 'demo.remote': '遠端設定',
      'demo.hint': '↑ 勾選左側方案，/etc/hosts 即時變化；點名稱查看單一方案',
      'demo.on': '已啟用 {n} 個方案', 'demo.readonly': '唯讀', 'demo.typing': '編輯中…',
      'demo.saved': '✓ 已寫入 /etc/hosts · 已清除 DNS 快取', 'demo.toggle': '啟用「{name}」',
      'p.dev': '開發環境', 'p.staging': '預發環境', 'p.adblock': '封鎖廣告',
      'c.dev': '# 本機開發服務', 'c.staging': '# 預發環境伺服器', 'c.adblock': '# 封鎖廣告與統計網域', 'c.team': '# 團隊共用設定',
      'c.remote': '# 來源：https://hosts.example.com/team.txt',
      'features.k': 'features', 'features.title': '把 hosts 當成一組可開關的方案來管理', 'features.sub': '每一項都來自應用程式的實際功能。',
      'f1.t': '多方案管理', 'f1.d': '建立多套本地 hosts 方案，依需要啟用、停用、複製或刪除；多個啟用方案組合後一起寫入。',
      'f2.t': '系統層級套用', 'f2.d': '組合內容寫入系統 /etc/hosts，寫入後自動清除 DNS 快取，修改立即生效。',
      'f3.t': '遠端方案', 'f3.d': '從 http / https 網址抓取 hosts 存成方案，可手動重新整理，也可每小時、每 6 小時或每天自動重新整理。',
      'f4.t': '自動備份', 'f4.d': '每次寫入前備份舊內容，保留最近 30 份，可從「檔案」選單在 Finder 中查看。',
      'f5.t': '選單列快速切換', 'f5.d': '狀態列圖示列出全部方案，點一下即可啟用或關閉，不必打開主視窗。',
      'f6.t': '為 hosts 量身打造的編輯器', 'f6.d': '註解、IP（含 IPv6）、主機名稱語法上色，尋找取代、⌘/ 批次註解，支援淺色與深色外觀。',
      'f7.t': '匯入與匯出', 'f7.d': '把本機 hosts 檔案匯入為方案，或把目前內容匯出為文字檔。',
      'f8.t': '保留原始內容', 'f8.d': '只改寫自己的管理區塊；寫入前重新讀取系統 hosts，其他工具寫入的內容原樣保留。',
      'f9.t': '防止誤操作', 'f9.d': '有未儲存的修改時，視窗關閉按鈕會顯示提示點，結束前再次確認。',
      'features.also': '# 另有：简体中文 / 繁體中文 / English 介面；Sparkle 依晶片架構分別推送更新',
      'how.k': 'how-it-works', 'how.title': '只改寫自己管理的那幾段', 'how.sub': '每個啟用的方案寫成一個帶標記的區塊，區塊外的內容原樣保留。',
      'term.system.k': '系統', 'term.system.v': '目前 /etc/hosts 的完整內容，可直接編輯並儲存。',
      'term.default.k': '預設', 'term.default.v': '剝離 HostsEditor 管理區塊後的基礎內容，唯讀檢視。',
      'term.local.k': '本地設定', 'term.local.v': '手動維護的方案，可編輯、啟用、刪除。',
      'term.remote.k': '遠端設定', 'term.remote.v': '從網址抓取的方案，支援重新整理。',
      'how.term': '寫入流程（示意）',
      'log.1': '重新讀取 /etc/hosts，保留外部改動', 'log.2': '組合基礎內容與已啟用方案', 'log.3': '備份舊內容（保留最近 30 份）',
      'log.5': '輔助程式寫入 /etc/hosts', 'log.8': '讀回並驗證寫入結果', 'log.9': '已生效',
      'sec.1': '主程式負責介面、方案管理、狀態列與遠端抓取，以一般使用者權限執行。',
      'sec.2': '輔助程式透過 SMAppService 註冊為背景常駐程式，主程式經 XPC 與它通訊。',
      'sec.3': '首次安裝或重新註冊輔助程式時需要系統授權。',
      'shot.k': 'screenshot', 'shot.title': '應用程式裡的樣子', 'shot.sub': '左側是方案列表，勾選即啟用；右側是帶語法上色的編輯器。',
      'shot.alt': 'HostsEditor 主畫面：左側方案列表，右側語法上色的 hosts 編輯器',
      'keys.k': 'keybindings', 'keys.title': '常用快速鍵',
      'k1': '新增本地方案 / 新增遠端方案', 'k2': '匯入 hosts 檔案為本地方案', 'k3': '儲存並套用', 'k4': '匯出目前內容',
      'k5': '尋找 / 取代', 'k6': '註解或取消註解選取的行', 'k7': '調整編輯器字體大小',
      'faq.k': 'getting-started', 'faq.title': '首次使用與常見問題',
      's1': '下載與晶片相符的 DMG，把 HostsEditor 拖進「應用程式」後打開。',
      's2': '首次讀取或寫入系統 hosts 時，應用程式會註冊特權輔助程式。',
      's3': '系統要求授權時，輸入管理者密碼。',
      's4': '若提示「需要允許背景項目」，前往「系統設定 › 一般 › 登入項目與延伸功能」允許 HostsEditor 的背景輔助程式，然後重新打開應用程式。',
      'q1.q': '出現 “couldn’t communicate with a helper application”',
      'q1.a1': '通常是系統裡殘留了舊版本的背景工作記錄。先結束 HostsEditor，再在「終端機」清除舊記錄：',
      'q1.a2': '確認 /Applications 與 ~/Applications 裡只有一份 HostsEditor.app，重新打開應用程式，點一次「啟用或修復背景輔助程式」，再觸發一次系統 hosts 的讀取或寫入。',
      'q2.q': '提示「需要允許背景項目」', 'q2.a': '前往「系統設定 › 一般 › 登入項目與延伸功能」，允許 HostsEditor 的背景輔助程式，然後重新啟動應用程式。',
      'q3.q': '確認自己的 Mac 是哪種晶片', 'q3.a': '打開「蘋果選單 › 關於這台 Mac」，看「晶片」或「處理器」一欄：顯示 Apple M 系列選 Apple 晶片版，顯示 Intel 選 Intel 版。',
      'copy': '拷貝', 'copied': '已拷貝',
      'dl.title': '下載 HostsEditor',
      'dl.sub': '需要 macOS 13.0 或更新版本。安裝檔已通過 Apple 公證，打開 DMG 後把應用程式拖進「應用程式」即可；內建 Sparkle 自動更新，只推送與本機晶片相符的版本。',
      'dl.all': '全部版本與更新說明 →',
      'foot.more': 'VanJay 的更多作品', 'foot.issues': '回報問題'
    }
  };

  /* ---------------- 语言 ---------------- */
  function normLang(v) {
    if (!v) {
      return null;
    }
    v = String(v).toLowerCase();
    if (v === 'en' || v.indexOf('en-') === 0) {
      return 'en';
    }
    if (/^zh[-_](tw|hk|mo|hant)/.test(v)) {
      return 'zh-Hant';
    }
    if (v.indexOf('zh') === 0) {
      return 'zh-Hans';
    }
    return null;
  }
  // 只看首选语言：中文按地区分简繁，其余一律英文
  function detectLang() {
    var list = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || 'en'];
    var first = String(list[0] || 'en').toLowerCase();
    if (first.indexOf('zh') === 0) {
      return normLang(first);
    }
    return 'en';
  }
  var lang = normLang(params.get('lang')) || normLang(load(KEY_LANG)) || detectLang();

  function t(key) {
    var d = T[lang] || T['zh-Hans'];
    return d[key] != null ? d[key] : (T['zh-Hans'][key] != null ? T['zh-Hans'][key] : key);
  }

  function applyLang() {
    doc.lang = lang === 'zh-Hans' ? 'zh-CN' : (lang === 'zh-Hant' ? 'zh-TW' : 'en');
    document.title = t('meta.title');
    setMeta('meta[name="description"]', t('meta.desc'));
    setMeta('meta[property="og:title"]', t('meta.title'));
    setMeta('meta[property="og:description"]', t('meta.desc'));
    each('[data-i18n]', function (el) {
      el.textContent = t(el.getAttribute('data-i18n'));
    });
    each('[data-i18n-html]', function (el) {
      el.innerHTML = t(el.getAttribute('data-i18n-html'));
    });
    each('[data-i18n-aria]', function (el) {
      el.setAttribute('aria-label', t(el.getAttribute('data-i18n-aria')));
    });
    each('[data-i18n-title]', function (el) {
      el.setAttribute('title', t(el.getAttribute('data-i18n-title')));
    });
    each('[data-i18n-alt]', function (el) {
      el.setAttribute('alt', t(el.getAttribute('data-i18n-alt')));
    });
    each('#langSeg button', function (b) {
      b.setAttribute('aria-pressed', String(b.getAttribute('data-lang') === lang));
    });
    if (!latestTag) {
      each('[data-ver]', function (el) {
        el.textContent = t('dl.latest');
      });
    }
    renderSnippet();
    if (demo) {
      demo.relabel();
    }
  }
  function setMeta(sel, v) {
    var m = document.querySelector(sel);
    if (m) {
      m.setAttribute('content', v);
    }
  }
  function each(sel, fn) {
    Array.prototype.forEach.call(document.querySelectorAll(sel), fn);
  }

  /* ---------------- 主题 ---------------- */
  var themePref = doc.getAttribute('data-theme-pref') || 'system';
  function applyTheme() {
    var resolved = themePref === 'system' ? (darkMQ.matches ? 'dark' : 'light') : themePref;
    doc.setAttribute('data-theme', resolved);
    doc.setAttribute('data-theme-pref', themePref);
    setMeta('meta[name="theme-color"]', resolved === 'dark' ? '#1e2127' : '#ffffff');
    each('#themeSeg button', function (b) {
      b.setAttribute('aria-pressed', String(b.getAttribute('data-theme-btn') === themePref));
    });
    var sb = document.getElementById('sbTheme');
    if (sb) {
      sb.textContent = resolved === 'dark' ? 'One Dark' : 'GitHub Light';
    }
  }
  var onScheme = function () {
    if (themePref === 'system') {
      applyTheme();
    }
  };
  if (darkMQ.addEventListener) {
    darkMQ.addEventListener('change', onScheme);
  } else if (darkMQ.addListener) {
    darkMQ.addListener(onScheme);
  }

  /* ---------------- hosts 语法高亮 ---------------- */
  function esc(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  // 与应用一致：整行注释为注释色；IP 与主机名分色；管理块标记额外上色
  function hl(s) {
    if (!s) {
      return '';
    }
    var trimmed = s.replace(/^\s+/, '');
    if (trimmed.charAt(0) === '#') {
      var mk = /^(\s*#\s*)(HostsEditor:(?:BEGIN|END):)(.*)$/.exec(s);
      if (mk) {
        return '<span class="tk-cm">' + esc(mk[1]) + '<span class="tk-mk">' + esc(mk[2]) + '</span><span class="tk-id">' + esc(mk[3]) + '</span></span>';
      }
      return '<span class="tk-cm">' + esc(s) + '</span>';
    }
    var m = /^(\s*)(\S+)(.*)$/.exec(s);
    if (!m) {
      return esc(s);
    }
    var rest = m[3];
    var hash = rest.indexOf('#');
    var hosts = hash >= 0 ? rest.slice(0, hash) : rest;
    var tail = hash >= 0 ? '<span class="tk-cm">' + esc(rest.slice(hash)) + '</span>' : '';
    return esc(m[1]) + '<span class="tk-ip">' + esc(m[2]) + '</span><span class="tk-h">' + esc(hosts) + '</span>' + tail;
  }

  /* ---------------- 演示数据 ---------------- */
  var SEP = '# ' + new Array(37).join('-');
  var BASE = [
    '##',
    '# Host Database',
    '#',
    '# localhost is used to configure the loopback interface',
    '# when the system is booting.  Do not change this entry.',
    '##',
    '127.0.0.1       localhost',
    '255.255.255.255 broadcasthost',
    '::1             localhost'
  ];
  var PROFILES = [
    { id: 'demo-dev', key: 'p.dev', on: true, body: function () {
      return [t('c.dev'), '127.0.0.1    api.example.dev', '127.0.0.1    web.example.dev', '127.0.0.1    admin.example.dev', '::1          api.example.dev'];
    } },
    { id: 'demo-staging', key: 'p.staging', on: false, body: function () {
      return [t('c.staging'), '10.0.8.21    api.example.com', '10.0.8.22    www.example.com', '10.0.8.23    cdn.example.com'];
    } },
    { id: 'demo-adblock', key: 'p.adblock', on: false, body: function () {
      return [t('c.adblock'), '0.0.0.0      ads.example.net', '0.0.0.0      tracker.example.net', '0.0.0.0      telemetry.example.org'];
    } },
    { id: 'demo-remote', name: 'team-shared', remote: true, on: true, body: function () {
      return [t('c.team'), t('c.remote'), '192.168.1.10  git.team.internal', '192.168.1.11  ci.team.internal', '192.168.1.12  wiki.team.internal'];
    } }
  ];
  function pname(p) {
    return p.name || t(p.key);
  }
  function blockLines(p) {
    return ['', '# HostsEditor:BEGIN:' + p.id, SEP, '# ' + pname(p) + ' [' + p.id + ']', SEP]
      .concat(p.body(), ['# HostsEditor:END:' + p.id]);
  }

  // 「工作方式」里的示例：固定展示开发环境一个块
  function renderSnippet() {
    var el = document.getElementById('howSnippet');
    if (!el) {
      return;
    }
    var lines = BASE.slice(6).concat(blockLines(PROFILES[0]));
    el.innerHTML = lines.map(hl).join('\n');
  }

  /* ---------------- 编辑器演示 ---------------- */
  var demo = null;
  function Demo() {
    var self = this;
    var code = document.getElementById('demoCode');
    var title = document.getElementById('demoTitle');
    var badge = document.getElementById('demoBadge');
    var state = document.getElementById('demoState');
    var toast = document.getElementById('demoToast');
    var side = document.getElementById('demoSide');
    var view = 'system';
    var job = null;          // 当前打字任务
    var visible = true;      // 演示区是否在视口内且页面可见
    var raf = 0;
    var autoTimer = 0;
    var autoStep = 0;
    var userTouched = false;
    var toastTimer = 0;
    var started = false;
    var pendingTimers = [];

    function reduced() {
      return reduceMQ.matches;
    }

    /* 侧栏 */
    function buildSide() {
      var local = document.getElementById('demoLocal');
      var remote = document.getElementById('demoRemote');
      local.innerHTML = '';
      remote.innerHTML = '';
      PROFILES.forEach(function (p) {
        var wrap = document.createElement('div');
        wrap.className = 'pf';
        wrap.setAttribute('data-id', p.id);
        var ck = document.createElement('button');
        ck.type = 'button';
        ck.className = 'ck';
        ck.setAttribute('role', 'checkbox');
        ck.innerHTML = '<i></i>';
        var nm = document.createElement('button');
        nm.type = 'button';
        nm.className = 'row';
        nm.setAttribute('data-view', p.id);
        nm.innerHTML = (p.remote ? '<svg class="cloud" viewBox="0 0 16 16" aria-hidden="true"><path d="M4.5 12.5h7.2a2.8 2.8 0 0 0 .4-5.6 4 4 0 0 0-7.6-.9A3.3 3.3 0 0 0 4.5 12.5z"/></svg>' : '') + '<span></span>';
        wrap.appendChild(ck);
        wrap.appendChild(nm);
        (p.remote ? remote : local).appendChild(wrap);
      });
    }
    function syncSide() {
      PROFILES.forEach(function (p) {
        var w = side.querySelector('.pf[data-id="' + p.id + '"]');
        var ck = w.querySelector('.ck');
        ck.setAttribute('aria-checked', String(p.on));
        ck.setAttribute('aria-label', t('demo.toggle').replace('{name}', pname(p)));
        w.querySelector('.row span:last-child').textContent = pname(p);
      });
      each('#demoSide .row', function (r) {
        var sel = r.getAttribute('data-view') === view;
        r.classList.toggle('is-sel', sel);
        r.setAttribute('aria-current', sel ? 'true' : 'false');
      });
      var n = PROFILES.filter(function (p) { return p.on; }).length;
      state.textContent = t('demo.on').replace('{n}', n);
    }

    /* 文本行 */
    function lineEl(text, blockId) {
      var d = document.createElement('div');
      d.className = 'l';
      if (blockId) {
        d.setAttribute('data-b', blockId);
      }
      d.innerHTML = '<span class="m" aria-hidden="true"></span><span class="t">' + hl(text) + '</span>';
      return d;
    }
    function linesFor(v) {
      if (v === 'system') {
        var out = BASE.map(function (s) { return [s, '']; });
        PROFILES.forEach(function (p) {
          if (p.on) {
            blockLines(p).forEach(function (s) { out.push([s, p.id]); });
          }
        });
        return out;
      }
      if (v === 'default') {
        return BASE.map(function (s) { return [s, '']; });
      }
      var p = PROFILES.filter(function (x) { return x.id === v; })[0];
      return p.body().map(function (s) { return [s, '']; });
    }
    function setHeader() {
      var p = PROFILES.filter(function (x) { return x.id === view; })[0];
      if (view === 'system') {
        title.textContent = '/etc/hosts';
      } else if (view === 'default') {
        title.textContent = '/etc/hosts — ' + t('demo.default');
      } else {
        title.textContent = (p.remote ? 'remote/' : 'profiles/') + p.id;
      }
      badge.textContent = view === 'default' ? t('demo.readonly') : '';
      badge.classList.toggle('on', view === 'default');
    }
    function renderStatic(animate) {
      finishJob();
      code.innerHTML = '';
      var frag = document.createDocumentFragment();
      linesFor(view).forEach(function (x) { frag.appendChild(lineEl(x[0], x[1])); });
      code.appendChild(frag);
      setHeader();
      syncSide();
      if (animate && !reduced()) {
        code.classList.remove('fadein');
        void code.offsetWidth;
        code.classList.add('fadein');
      }
    }

    /* 打字引擎：items = [{el, text}]，按字符逐步写入 */
    function typeLines(items, msPerChar, linePause, onDone) {
      finishJob();
      job = { items: items, i: 0, c: 0, ms: msPerChar, pause: linePause, acc: 0, last: 0, wait: 0, onDone: onDone };
      if (reduced()) {
        finishJob();
        return;
      }
      tick();
    }
    function paintLine(it, n, caret) {
      it.el.querySelector('.t').innerHTML = hl(it.text.slice(0, n)) + (caret ? '<span class="caret"></span>' : '');
    }
    function step(now) {
      raf = 0;
      if (!job) {
        return;
      }
      if (!visible) {
        job.last = 0;
        return;
      }
      var dt = job.last ? Math.min(64, now - job.last) : 16;
      job.last = now;
      if (job.wait > 0) {
        job.wait -= dt;
        tick();
        return;
      }
      job.acc += dt;
      var it = job.items[job.i];
      var add = Math.floor(job.acc / job.ms);
      if (add > 0) {
        job.acc -= add * job.ms;
        job.c = Math.min(it.text.length, job.c + add);
        paintLine(it, job.c, true);
        keepInView(it.el);
      }
      if (job.c >= it.text.length) {
        paintLine(it, it.text.length, false);
        job.i += 1;
        job.c = 0;
        job.wait = job.pause;
        if (job.i >= job.items.length) {
          var done = job.onDone;
          job = null;
          if (done) {
            done();
          }
          return;
        }
        paintLine(job.items[job.i], 0, true);
      }
      tick();
    }
    function tick() {
      if (!raf && visible) {
        raf = requestAnimationFrame(step);
      }
    }
    // 立即完成当前打字任务（用户快速操作或切换语言时）
    function finishJob() {
      if (raf) {
        cancelAnimationFrame(raf);
        raf = 0;
      }
      // onDone 可能串联启动下一个任务，循环直到全部完成
      while (job) {
        var j = job;
        job = null;
        for (var k = j.i; k < j.items.length; k++) {
          paintLine(j.items[k], j.items[k].text.length, false);
        }
        if (j.onDone) {
          j.onDone();
        }
      }
      if (raf) {
        cancelAnimationFrame(raf);
        raf = 0;
      }
    }
    // 编辑器内部滚动跟随光标（只滚动编辑器容器，不影响页面）
    function keepInView(el) {
      var wrap = code.parentNode;
      var top = el.offsetTop;
      if (top + 28 > wrap.scrollTop + wrap.clientHeight) {
        wrap.scrollTop = top - wrap.clientHeight + 48;
      } else if (top < wrap.scrollTop) {
        wrap.scrollTop = Math.max(0, top - 20);
      }
    }
    function later(fn, ms) {
      var id = setTimeout(function () {
        pendingTimers.splice(pendingTimers.indexOf(id), 1);
        fn();
      }, ms);
      pendingTimers.push(id);
    }
    function flushTimers() {
      pendingTimers.slice().forEach(function (id) {
        clearTimeout(id);
      });
      pendingTimers = [];
      each('#demoCode .l.del', function (el) {
        el.parentNode.removeChild(el);
      });
      each('#demoCode .l.add, #demoCode .l.fade', function (el) {
        el.classList.remove('add', 'fade');
      });
    }

    function showToast() {
      clearTimeout(toastTimer);
      toast.textContent = t('demo.saved');
      toast.classList.add('on');
      toastTimer = setTimeout(function () {
        toast.classList.remove('on');
      }, 2600);
    }

    /* 勾选/取消某个方案：以 diff 形式在「系统」视图里增删管理块 */
    function toggle(id) {
      finishJob();
      flushTimers();
      var p = PROFILES.filter(function (x) { return x.id === id; })[0];
      if (view !== 'system') {
        view = 'system';
        renderStatic(false);
      }
      p.on = !p.on;
      syncSide();
      if (p.on) {
        // 找到插入点：排在它后面的第一个已启用方案块之前
        var idx = PROFILES.indexOf(p);
        var before = null;
        for (var k = idx + 1; k < PROFILES.length && !before; k++) {
          if (PROFILES[k].on) {
            before = code.querySelector('.l[data-b="' + PROFILES[k].id + '"]');
          }
        }
        var items = blockLines(p).map(function (s) {
          var el = lineEl('', p.id);
          el.classList.add('add');
          el.querySelector('.m').textContent = '+';
          code.insertBefore(el, before);
          return { el: el, text: s };
        });
        keepInView(items[0].el);
        typeLines(items, 11, 40, function () {
          showToast();
          later(function () {
            items.forEach(function (it) {
              it.el.classList.remove('add');
              it.el.classList.add('fade');
              it.el.querySelector('.m').textContent = '';
            });
          }, 900);
        });
      } else {
        var dels = code.querySelectorAll('.l[data-b="' + p.id + '"]');
        if (dels.length) {
          keepInView(dels[0]);
        }
        Array.prototype.forEach.call(dels, function (el) {
          el.classList.add('del');
          el.querySelector('.m').textContent = '-';
        });
        var drop = function () {
          Array.prototype.forEach.call(dels, function (el) {
            if (el.parentNode) {
              el.parentNode.removeChild(el);
            }
          });
          showToast();
        };
        if (reduced()) {
          drop();
        } else {
          later(function () {
            Array.prototype.forEach.call(dels, function (el) {
              el.classList.add('gone');
            });
            later(drop, 360);
          }, 650);
        }
      }
    }

    function select(v) {
      if (v === view) {
        return;
      }
      finishJob();
      flushTimers();
      view = v;
      renderStatic(true);
      code.parentNode.scrollTop = 0;
    }

    /* 自动演示：用户未操作时按脚本轮流切换方案 */
    var SCRIPT = ['demo-staging', 'demo-dev', 'demo-adblock', 'demo-staging', 'demo-dev', 'demo-adblock'];
    function scheduleAuto(ms) {
      clearTimeout(autoTimer);
      if (userTouched || reduced()) {
        return;
      }
      autoTimer = setTimeout(function () {
        if (!visible || job) {
          scheduleAuto(1200);
          return;
        }
        toggle(SCRIPT[autoStep % SCRIPT.length]);
        autoStep += 1;
        scheduleAuto(4200);
      }, ms);
    }
    function stopAuto() {
      userTouched = true;
      clearTimeout(autoTimer);
    }

    /* 首次进入：基础内容逐行出现，已启用的块逐字打出 */
    function intro() {
      started = true;
      code.innerHTML = '';
      setHeader();
      syncSide();
      if (reduced()) {
        renderStatic(false);
        return;
      }
      var all = linesFor('system').map(function (x) {
        var el = lineEl('', x[1]);
        code.appendChild(el);
        return { el: el, text: x[0], base: !x[1] };
      });
      var baseItems = all.filter(function (x) { return x.base; });
      var rest = all.filter(function (x) { return !x.base; });
      typeLines(baseItems, 2, 30, function () {
        typeLines(rest, 9, 50, function () {
          scheduleAuto(2600);
        });
      });
    }

    side.addEventListener('click', function (e) {
      var ck = e.target.closest('.ck');
      var row = e.target.closest('.row');
      if (ck) {
        stopAuto();
        toggle(ck.parentNode.getAttribute('data-id'));
      } else if (row) {
        stopAuto();
        select(row.getAttribute('data-view'));
      }
    });

    // 不在视口或页面隐藏时暂停 rAF 和自动演示
    function setVisible(v) {
      visible = v && !document.hidden;
      if (visible) {
        if (!started) {
          intro();
        } else if (job) {
          job.last = 0;
          tick();
        }
      } else if (raf) {
        cancelAnimationFrame(raf);
        raf = 0;
      }
    }
    var inView = true;
    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (ents) {
        inView = ents[0].isIntersecting;
        setVisible(inView);
      }, { threshold: 0.15 }).observe(document.getElementById('demo'));
    }
    document.addEventListener('visibilitychange', function () {
      setVisible(inView);
    });

    buildSide();
    syncSide();
    setHeader();

    // 切换语言：直接重绘当前视图，不再重放打字
    self.relabel = function () {
      if (!started) {
        syncSide();
        setHeader();
        return;
      }
      flushTimers();
      renderStatic(false);
    };
    self.start = function () {
      setVisible(inView);
    };
  }

  /* ---------------- 下载链接 ---------------- */
  var latestTag = '';
  function fmtSize(b) {
    return (b / 1048576).toFixed(1) + ' MB';
  }
  // 把 Release 信息应用到下载按钮与版本号
  function applyRelease(d) {
    var found = {};
    (d.assets || []).forEach(function (a) {
      if (/_arm64\.dmg$/i.test(a.name)) {
        found.arm64 = a;
      } else if (/_x86_64\.dmg$/i.test(a.name)) {
        found.x86_64 = a;
      }
    });
    Object.keys(found).forEach(function (arch) {
      var a = found[arch];
      each('a[data-dl="' + arch + '"]', function (el) {
        el.href = a.browser_download_url;
      });
      each('[data-dl-meta="' + arch + '"]', function (el) {
        el.textContent = arch + ' · ' + fmtSize(a.size);
      });
    });
    if (d.tag_name) {
      latestTag = d.tag_name;
      each('[data-ver]', function (el) {
        el.textContent = latestTag;
      });
    }
  }
  // 请求 GitHub API 换成带版本号的直链；结果缓存 30 分钟，减少匿名限流；失败时保留 releases/latest
  function loadRelease() {
    var KEY = 'hostseditor.release';
    try {
      var cached = JSON.parse(load(KEY) || 'null');
      if (cached && Date.now() - cached.at < 1800000 && cached.data) {
        applyRelease(cached.data);
        return;
      }
    } catch (e) {
      // 缓存损坏时忽略，重新请求
    }
    if (!window.fetch) {
      return;
    }
    fetch('https://api.github.com/repos/wangwanjie/HostsEditor/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
      .then(function (r) {
        if (!r.ok) {
          throw new Error('HTTP ' + r.status);
        }
        return r.json();
      })
      .then(function (d) {
        var slim = {
          tag_name: d.tag_name,
          assets: (d.assets || []).map(function (a) {
            return { name: a.name, size: a.size, browser_download_url: a.browser_download_url };
          })
        };
        store(KEY, JSON.stringify({ at: Date.now(), data: slim }));
        applyRelease(slim);
      })
      .catch(function () {
        // 失败时保留 releases/latest 回退链接
      });
  }

  /* ---------------- 其他交互 ---------------- */
  function initReveal() {
    var els = document.querySelectorAll('.reveal');
    if (!('IntersectionObserver' in window) || reduceMQ.matches) {
      Array.prototype.forEach.call(els, function (el) { el.classList.add('in'); });
      var lg = document.getElementById('howLog');
      if (lg) {
        lg.classList.add('play');
      }
      return;
    }
    var io = new IntersectionObserver(function (ents) {
      ents.forEach(function (en) {
        if (en.isIntersecting) {
          en.target.classList.add('in');
          io.unobserve(en.target);
        }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    Array.prototype.forEach.call(els, function (el, i) {
      // 同一行的卡片错开出现
      el.style.transitionDelay = (el.classList.contains('card') ? (i % 3) * 70 : 0) + 'ms';
      io.observe(el);
    });
    // 写入流程日志逐行出现
    var log = document.getElementById('howLog');
    if (log) {
      Array.prototype.forEach.call(log.children, function (li, i) {
        li.style.transitionDelay = (i * 160) + 'ms';
      });
      var lo = new IntersectionObserver(function (ents) {
        if (ents[0].isIntersecting) {
          log.classList.add('play');
          lo.disconnect();
        }
      }, { threshold: 0.3 });
      lo.observe(log);
    }
  }

  // 卡片悬停高光跟随指针
  function initCards() {
    each('.card', function (c) {
      c.addEventListener('pointermove', function (e) {
        var r = c.getBoundingClientRect();
        c.style.setProperty('--mx', (e.clientX - r.left) + 'px');
        c.style.setProperty('--my', (e.clientY - r.top) + 'px');
      });
    });
  }

  function initCopy() {
    each('[data-copy]', function (b) {
      b.addEventListener('click', function () {
        var text = b.getAttribute('data-copy');
        var done = function () {
          b.textContent = t('copied');
          setTimeout(function () {
            b.textContent = t('copy');
          }, 1600);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(done, function () {});
        }
      });
    });
  }

  // 底部状态栏：按滚动位置显示行号与当前区块
  function initStatusbar() {
    var ln = document.getElementById('sbLn');
    var sec = document.getElementById('sbSec');
    if (!ln) {
      return;
    }
    var ticking = false;
    var update = function () {
      ticking = false;
      ln.textContent = 'Ln ' + (Math.floor(window.scrollY / 20) + 1) + ', Col 1';
    };
    window.addEventListener('scroll', function () {
      if (!ticking) {
        ticking = true;
        requestAnimationFrame(update);
      }
    }, { passive: true });
    update();
    if ('IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (ents) {
        ents.forEach(function (en) {
          if (en.isIntersecting) {
            sec.textContent = 'index.html › ' + en.target.getAttribute('data-section');
          }
        });
      }, { rootMargin: '-45% 0px -50% 0px' });
      each('[data-section]', function (s) { io.observe(s); });
    }
  }

  /* ---------------- 启动 ---------------- */
  each('#langSeg button', function (b) {
    b.addEventListener('click', function () {
      lang = b.getAttribute('data-lang');
      store(KEY_LANG, lang);
      applyLang();
    });
  });
  each('#themeSeg button', function (b) {
    b.addEventListener('click', function () {
      themePref = b.getAttribute('data-theme-btn');
      store(KEY_THEME, themePref);
      applyTheme();
    });
  });

  demo = new Demo();
  applyLang();
  applyTheme();
  initReveal();
  initCards();
  initCopy();
  initStatusbar();
  demo.start();
  loadRelease();
})();
