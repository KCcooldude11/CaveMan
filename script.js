// ===========================
// DESKTOP ODYSSEY
// A Fake Desktop Puzzle Game
// ===========================

// ===========================
// GAME STATE
// ===========================

let gameState = {
    internetConnected: false,
    wifiEnabled: false,
    firewallEnabled: true,
    adminPasswordEntered: false,
    antivirusRunning: true,
    systemTimeFixed: false,
    hiddenClueRevealed: false,
    networkSettingsUnlocked: false,
    routerIssueFixed: false,
    notesOpened: false,
    gameWon: false
};

const ADMIN_PASSWORD = "wisdom";

let openWindows = [];
let nextWindowId = 1;
let highestZIndex = 100;
let draggedWindow = null;
let dragOffset = { x: 0, y: 0 };

// ===========================
// DESKTOP ICONS DATA
// ===========================

const desktopIcons = [
    { id: "browser", icon: "🌐", label: "Internet Browser", app: "browser" },
    { id: "settings", icon: "⚙️", label: "Settings", app: "settings" },
    { id: "firewall", icon: "🛡️", label: "Firewall Utility", app: "firewall" },
    { id: "notes", icon: "📝", label: "Notes", app: "notes" },
    { id: "taskmanager", icon: "📊", label: "Task Manager", app: "taskmanager" },
    { id: "router", icon: "📡", label: "Router Utility", app: "router" },
    { id: "recyclebin", icon: "🗑️", label: "Recycle Bin", app: "recyclebin" },
    { id: "myputer", icon: "💻", label: "My Puter", app: "myputer" }
];

// ===========================
// APP DEFINITIONS
// ===========================

const apps = {
    browser: {
        title: "🌐 Internet Browser",
        width: 600,
        height: 500,
        render: () => {
            if (gameState.internetConnected) {
                return `
                    <div class="browser-online">
                        <h1>🎉 CONNECTION SUCCESSFUL!</h1>
                        <p class="mb-2">Welcome to the World Wide Web™</p>
                        <p style="color: #666; font-size: 14px;">You are now connected to the information superhighway.</p>
                        <p style="color: #666; font-size: 14px; margin-top: 20px;">
                            Current page: https://www.youdidit.com/success
                        </p>
                    </div>
                `;
            } else {
                return `
                    <div class="browser-offline">
                        <h2>🚫 No Internet Connection</h2>
                        <p class="mb-3">Unable to connect to the internet.</p>
                        <p style="color: #999; font-size: 14px; margin-bottom: 20px;">
                            Please check your network connection and try again.
                        </p>
                        <button class="btn btn-primary" onclick="attemptBrowserRetry()">Retry Connection</button>
                    </div>
                `;
            }
        }
    },
    
    settings: {
        title: "⚙️ Settings",
        width: 500,
        height: 600,
        render: () => {
            if (!gameState.notesOpened) {
                gameState.notesOpened = true;
            }
            
            return `
                <div class="settings-section">
                    <h3>System Settings</h3>
                    <p style="color: #666; font-size: 14px;">Configure system preferences and network options</p>
                </div>
                
                <div class="settings-section ${!gameState.networkSettingsUnlocked ? 'locked' : ''}">
                    <h3>Network & Internet</h3>
                    ${!gameState.networkSettingsUnlocked ? 
                        '<p style="color: var(--error); font-weight: 600;">⚠️ Access blocked by Firewall Guardian</p>' : 
                        `
                        <div class="setting-row">
                            <div>
                                <div style="font-weight: 600;">Wi-Fi</div>
                                <div style="font-size: 12px; color: #666;">Wireless network adapter</div>
                            </div>
                            <div class="toggle-switch ${gameState.wifiEnabled ? 'on' : ''}" onclick="attemptWifiToggle()"></div>
                        </div>
                        <div class="setting-row">
                            <div>
                                <div style="font-weight: 600;">Status</div>
                                <div style="font-size: 12px; color: #666;">${gameState.wifiEnabled ? 'Connected' : 'Disabled'}</div>
                            </div>
                        </div>
                        `
                    }
                </div>
                
                <div class="settings-section">
                    <h3>Display</h3>
                    <p style="color: #666; font-size: 14px;">Resolution: 1920x1080</p>
                </div>
                
                <div class="settings-section">
                    <h3>About</h3>
                    <p style="color: #666; font-size: 14px;">DesktopOS Professional Edition</p>
                    <p style="color: #666; font-size: 12px; margin-top: 8px;">Version 10.2.5</p>
                </div>
            `;
        }
    },
    
    firewall: {
        title: "🛡️ Firewall Guardian",
        width: 500,
        height: 450,
        render: () => {
            return `
                <div style="text-align: center; margin-bottom: 24px;">
                    <h2>Firewall Guardian</h2>
                    <p style="color: #666;">Protecting you from dangerous connectivity</p>
                </div>
                
                <div class="settings-section">
                    <h3>Status</h3>
                    <div class="setting-row">
                        <div>
                            <div style="font-weight: 600;">Firewall</div>
                            <div style="font-size: 12px; color: #666;">
                                ${gameState.firewallEnabled ? 'Active and protecting' : 'Disabled'}
                            </div>
                        </div>
                        <div style="color: ${gameState.firewallEnabled ? 'var(--success)' : 'var(--error)'}; font-weight: 700; font-size: 20px;">
                            ${gameState.firewallEnabled ? '✓' : '✗'}
                        </div>
                    </div>
                </div>
                
                ${gameState.firewallEnabled ? `
                    <div class="settings-section">
                        <h3>Disable Firewall</h3>
                        <p style="color: var(--warning); font-size: 13px; margin-bottom: 12px;">
                            ⚠️ Disabling the firewall requires administrator privileges
                        </p>
                        <p style="font-size: 13px; color: #666; margin-bottom: 16px;">
                            Are you sure you want to turn off the firewall? The firewall has feelings.
                        </p>
                        <div class="password-input-group">
                            <input type="password" id="adminPasswordInput" placeholder="Admin password" />
                            <button onclick="attemptFirewallDisable()">Disable</button>
                        </div>
                    </div>
                ` : `
                    <div class="settings-section">
                        <p style="color: var(--success); font-weight: 600;">✓ Firewall has been disabled</p>
                        <p style="font-size: 13px; color: #666;">Network settings are now accessible</p>
                    </div>
                `}
            `;
        }
    },
    
    notes: {
        title: "📝 Notes",
        width: 450,
        height: 400,
        render: () => {
            return `
                <h3 style="margin-bottom: 16px;">Important Reminders</h3>
                <div style="background: #fffef0; border: 1px solid #e6db74; padding: 16px; border-radius: 4px; margin-bottom: 16px;">
                    <p style="font-size: 14px; line-height: 1.6;">
                        <strong>Admin Access Note:</strong><br><br>
                        The admin password hint is hidden under the clock.<br><br>
                        Check the taskbar clock for more information.
                    </p>
                </div>
                <div style="background: #f5f5f5; padding: 16px; border-radius: 4px;">
                    <p style="font-size: 13px; color: #666;">
                        Other notes:<br>
                        - Remember to update antivirus<br>
                        - Check router settings if Wi-Fi fails<br>
                        - Do not disable firewall unless necessary
                    </p>
                </div>
            `;
        }
    },
    
    taskmanager: {
        title: "📊 Task Manager",
        width: 550,
        height: 500,
        render: () => {
            const processes = [
                { name: "system.exe", status: "Running", canEnd: false },
                { name: "explorer.exe", status: "Running", canEnd: false },
                { name: "wifi_adapter.exe", status: "Running", canEnd: false },
                { name: "guarddog.exe", status: gameState.antivirusRunning ? "Running" : "Stopped", canEnd: gameState.antivirusRunning }
            ];
            
            return `
                <h3 style="margin-bottom: 16px;">Running Processes</h3>
                <p style="color: #666; font-size: 13px; margin-bottom: 20px;">
                    Manage running applications and processes
                </p>
                <ul class="process-list">
                    ${processes.map(proc => `
                        <li class="process-item">
                            <div>
                                <div class="process-name">${proc.name}</div>
                                <div style="font-size: 11px; color: #666;">${proc.status}</div>
                            </div>
                            ${proc.canEnd ? 
                                '<button class="end-process-btn" onclick="endAntivirusProcess()">End Task</button>' : 
                                '<span style="font-size: 12px; color: #999;">Protected</span>'
                            }
                        </li>
                    `).join('')}
                </ul>
                ${gameState.antivirusRunning ? `
                    <p style="margin-top: 20px; font-size: 13px; color: var(--warning);">
                        ⚠️ guarddog.exe is interfering with system time settings
                    </p>
                ` : ''}
            `;
        }
    },
    
    router: {
        title: "📡 Router Utility",
        width: 500,
        height: 400,
        render: () => {
            if (!gameState.wifiEnabled) {
                return `
                    <div style="text-align: center; padding: 60px 20px;">
                        <h3 style="color: #666;">Router utility requires Wi-Fi to be enabled</h3>
                        <p style="color: #999; font-size: 14px; margin-top: 12px;">
                            Please enable Wi-Fi in network settings first.
                        </p>
                    </div>
                `;
            }
            
            return `
                <div style="text-align: center; margin-bottom: 24px;">
                    <h2>Router Configuration</h2>
                    <p style="color: #666;">Home network: HOME_WIFI_5G</p>
                </div>
                
                <div class="settings-section">
                    <h3>Connection Status</h3>
                    <p style="color: #666; font-size: 14px;">
                        Router: Online<br>
                        Signal: Excellent<br>
                        IP: 192.168.1.42
                    </p>
                </div>
                
                ${!gameState.routerIssueFixed ? `
                    <div class="settings-section">
                        <h3 style="color: var(--error);">⚠️ Safety Mode Active</h3>
                        <p style="font-size: 14px; margin-bottom: 16px; line-height: 1.6;">
                            Your router is in DNS Safety Mode to protect you from the dangerous internet.
                            The internet contains websites.
                        </p>
                        <p style="font-size: 13px; color: #666; margin-bottom: 16px;">
                            Disable safety mode to allow full internet access?
                        </p>
                        <button class="btn btn-primary" onclick="disableRouterSafetyMode()">
                            I Accept The Risk
                        </button>
                    </div>
                ` : `
                    <div class="settings-section">
                        <p style="color: var(--success); font-weight: 600;">✓ Safety mode disabled</p>
                        <p style="font-size: 13px; color: #666;">Full internet access enabled</p>
                    </div>
                `}
            `;
        }
    },
    
    recyclebin: {
        title: "🗑️ Recycle Bin",
        width: 450,
        height: 400,
        render: () => {
            return `
                <div style="text-align: center; padding: 60px 20px;">
                    <div style="font-size: 64px; margin-bottom: 20px;">🗑️</div>
                    <h3 style="color: #666;">Recycle Bin is empty</h3>
                    <p style="color: #999; font-size: 14px; margin-top: 12px;">
                        No deleted files to display.
                    </p>
                </div>
            `;
        }
    },
    
    myputer: {
        title: "💻 My Puter",
        width: 500,
        height: 450,
        render: () => {
            return `
                <h3 style="margin-bottom: 20px;">Computer Information</h3>
                <div class="settings-section">
                    <h3>System</h3>
                    <p style="font-size: 14px; line-height: 1.8; color: #666;">
                        Computer Name: DESK-TOP<br>
                        Processor: Intel Confusion i7<br>
                        RAM: 8 GB<br>
                        System Type: 64-bit<br>
                        OS: DesktopOS Professional
                    </p>
                </div>
                <div class="settings-section">
                    <h3>Storage</h3>
                    <p style="font-size: 14px; color: #666;">
                        C: Drive (250 GB)<br>
                        Used: 180 GB<br>
                        Free: 70 GB
                    </p>
                </div>
            `;
        }
    }
};

// ===========================
// CLOCK WINDOW (Special)
// ===========================

function renderClockWindow() {
    const timeDisplay = gameState.systemTimeFixed ? "12:34" : "̷̗̈1̸̰͝2̴̜̄:̶̞̃3̵̤̆4̸͎̈";
    
    return `
        <div class="clock-panel">
            <h3>System Time</h3>
            <div class="clock-display-large ${!gameState.systemTimeFixed ? 'corrupted' : ''}">
                ${timeDisplay}
            </div>
            ${!gameState.systemTimeFixed ? `
                <p style="color: var(--error); font-size: 14px; margin-bottom: 16px;">
                    ⚠️ System time is corrupted
                </p>
                <button class="time-fix-btn" onclick="attemptTimeFix()" ${gameState.antivirusRunning ? 'disabled' : ''}>
                    Fix System Time
                </button>
                ${gameState.antivirusRunning ? `
                    <p style="color: var(--warning); font-size: 13px; margin-top: 12px;">
                        Cannot modify time: guarddog.exe is blocking access
                    </p>
                ` : ''}
            ` : `
                <p style="color: var(--success); font-weight: 600; margin-bottom: 20px;">
                    ✓ System time corrected
                </p>
            `}
            
            ${gameState.hiddenClueRevealed ? `
                <div class="hidden-clue">
                    <div style="font-size: 12px; color: #856404; margin-bottom: 8px;">HIDDEN MESSAGE:</div>
                    <div style="font-size: 16px; color: #000;">
                        "Admin password is: ${ADMIN_PASSWORD}"
                    </div>
                </div>
            ` : ''}
        </div>
    `;
}

// ===========================
// INITIALIZATION
// ===========================

function initGame() {
    renderDesktop();
    renderTaskbar();
    updateTaskbarClock();
    
    // Welcome toast
    showToast("Welcome to your desktop. Your goal: get internet access.", "info");
}

// ===========================
// RENDERING
// ===========================

function renderDesktop() {
    const iconsContainer = document.getElementById("desktopIcons");
    iconsContainer.innerHTML = desktopIcons.map(icon => `
        <div class="desktop-icon" onclick="openApp('${icon.app}')">
            <div class="icon-image">${icon.icon}</div>
            <div class="icon-label">${icon.label}</div>
        </div>
    `).join('');
}

function renderTaskbar() {
    updateTaskbarClock();
    updateWifiIcon();
}

function updateTaskbarClock() {
    const clockEl = document.getElementById("taskbarClock");
    if (gameState.systemTimeFixed) {
        clockEl.textContent = "12:34";
        clockEl.style.color = "white";
    } else {
        clockEl.textContent = "??:??";
        clockEl.style.color = "#ff6b6b";
    }
}

function updateWifiIcon() {
    const wifiIcon = document.getElementById("wifiStatus");
    if (gameState.internetConnected) {
        wifiIcon.textContent = "📶";
    } else if (gameState.wifiEnabled) {
        wifiIcon.textContent = "📡";
    } else {
        wifiIcon.textContent = "📵";
    }
}

function renderWindows() {
    const container = document.getElementById("windowsContainer");
    container.innerHTML = openWindows.map(win => {
        const appDef = win.appId === 'clock' ? null : apps[win.appId];
        const title = win.appId === 'clock' ? '🕐 Date & Time' : appDef.title;
        const content = win.appId === 'clock' ? renderClockWindow() : appDef.render();
        
        return `
            <div class="window" id="window-${win.id}" 
                 style="left: ${win.x}px; top: ${win.y}px; width: ${win.width}px; height: ${win.height}px; z-index: ${win.zIndex};"
                 onclick="bringToFront(${win.id})">
                <div class="window-titlebar" onmousedown="startDragging(event, ${win.id})">
                    <div class="window-title">${title}</div>
                    <div class="window-controls">
                        <button class="window-control-btn close" onclick="closeWindow(${win.id}); event.stopPropagation();">✕</button>
                    </div>
                </div>
                <div class="window-content">
                    ${content}
                </div>
            </div>
        `;
    }).join('');
}

// ===========================
// WINDOW MANAGEMENT
// ===========================

function openApp(appId) {
    // Check if window already open
    const existing = openWindows.find(w => w.appId === appId);
    if (existing) {
        bringToFront(existing.id);
        return;
    }
    
    const appDef = appId === 'clock' ? { width: 450, height: 400 } : apps[appId];
    if (!appDef && appId !== 'clock') return;
    
    const window = {
        id: nextWindowId++,
        appId: appId,
        x: 100 + (openWindows.length * 30),
        y: 50 + (openWindows.length * 30),
        width: appDef.width,
        height: appDef.height,
        zIndex: ++highestZIndex
    };
    
    openWindows.push(window);
    renderWindows();
}

function closeWindow(windowId) {
    openWindows = openWindows.filter(w => w.id !== windowId);
    renderWindows();
}

function bringToFront(windowId) {
    const window = openWindows.find(w => w.id === windowId);
    if (window) {
        window.zIndex = ++highestZIndex;
        renderWindows();
    }
}

function startDragging(event, windowId) {
    event.preventDefault();
    const window = openWindows.find(w => w.id === windowId);
    if (!window) return;
    
    draggedWindow = window;
    const windowEl = document.getElementById(`window-${windowId}`);
    const rect = windowEl.getBoundingClientRect();
    
    dragOffset.x = event.clientX - rect.left;
    dragOffset.y = event.clientY - rect.top;
    
    document.addEventListener('mousemove', onDragMove);
    document.addEventListener('mouseup', onDragEnd);
}

function onDragMove(event) {
    if (!draggedWindow) return;
    
    draggedWindow.x = event.clientX - dragOffset.x;
    draggedWindow.y = event.clientY - dragOffset.y;
    
    // Keep window on screen
    draggedWindow.x = Math.max(0, Math.min(draggedWindow.x, window.innerWidth - 200));
    draggedWindow.y = Math.max(0, Math.min(draggedWindow.y, window.innerHeight - 150));
    
    renderWindows();
}

function onDragEnd() {
    draggedWindow = null;
    document.removeEventListener('mousemove', onDragMove);
    document.removeEventListener('mouseup', onDragEnd);
}

// ===========================
// TOAST SYSTEM
// ===========================

function showToast(message, type = 'info') {
    const container = document.getElementById('toastContainer');
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.textContent = message;
    
    container.appendChild(toast);
    
    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => toast.remove(), 300);
    }, 4000);
}

// ===========================
// GAME LOGIC / PUZZLE ACTIONS
// ===========================

function attemptBrowserRetry() {
    if (!gameState.internetConnected) {
        if (!gameState.wifiEnabled) {
            showToast("No internet connection. Check your network settings.", "error");
        } else if (!gameState.routerIssueFixed) {
            showToast("Connection blocked. Check router settings.", "warning");
        } else {
            showToast("Connection failed. Something is still wrong.", "error");
        }
    }
    checkProgression();
}

function attemptWifiToggle() {
    if (!gameState.networkSettingsUnlocked) {
        showToast("Network settings are blocked by the firewall.", "error");
        return;
    }
    
    gameState.wifiEnabled = !gameState.wifiEnabled;
    renderWindows();
    updateWifiIcon();
    
    if (gameState.wifiEnabled) {
        showToast("Wi-Fi enabled successfully!", "success");
        showToast("Check the Router Utility to configure connection settings.", "info");
    } else {
        showToast("Wi-Fi disabled.", "info");
    }
    
    checkProgression();
}

function attemptFirewallDisable() {
    const input = document.getElementById('adminPasswordInput');
    const enteredPassword = input.value.trim().toLowerCase();
    
    if (enteredPassword === ADMIN_PASSWORD) {
        gameState.firewallEnabled = false;
        gameState.adminPasswordEntered = true;
        gameState.networkSettingsUnlocked = true;
        
        showToast("Admin password accepted! Firewall disabled.", "success");
        showToast("Network settings are now accessible.", "info");
        
        renderWindows();
        checkProgression();
    } else if (enteredPassword === "") {
        showToast("Please enter a password.", "warning");
    } else {
        showToast("Incorrect password. Access denied.", "error");
    }
}

function endAntivirusProcess() {
    gameState.antivirusRunning = false;
    showToast("guarddog.exe has been terminated.", "success");
    showToast("System time settings are now accessible.", "info");
    renderWindows();
}

function attemptTimeFix() {
    if (gameState.antivirusRunning) {
        showToast("Cannot modify time: guarddog.exe is blocking access.", "error");
        return;
    }
    
    gameState.systemTimeFixed = true;
    gameState.hiddenClueRevealed = true;
    
    showToast("System time has been corrected!", "success");
    showToast("A hidden message has been revealed...", "info");
    
    updateTaskbarClock();
    renderWindows();
}

function disableRouterSafetyMode() {
    gameState.routerIssueFixed = true;
    showToast("DNS Safety Mode disabled.", "success");
    showToast("Full internet access is now available!", "info");
    renderWindows();
    checkProgression();
}

// ===========================
// PROGRESSION CHECKER
// ===========================

function checkProgression() {
    // Win condition: Wi-Fi enabled + router issue fixed
    if (gameState.wifiEnabled && 
        gameState.routerIssueFixed && 
        !gameState.internetConnected) {
        
        gameState.internetConnected = true;
        updateWifiIcon();
        
        setTimeout(() => {
            showToast("🎉 INTERNET CONNECTION ESTABLISHED!", "success");
            setTimeout(() => {
                showWinScreen();
            }, 2000);
        }, 500);
    }
}

// ===========================
// WIN SCREEN
// ===========================

function showWinScreen() {
    gameState.gameWon = true;
    document.getElementById('winScreen').classList.remove('hidden');
}

function hideWinScreen() {
    document.getElementById('winScreen').classList.add('hidden');
}

function restartGame() {
    // Reset state
    gameState = {
        internetConnected: false,
        wifiEnabled: false,
        firewallEnabled: true,
        adminPasswordEntered: false,
        antivirusRunning: true,
        systemTimeFixed: false,
        hiddenClueRevealed: false,
        networkSettingsUnlocked: false,
        routerIssueFixed: false,
        notesOpened: false,
        gameWon: false
    };
    
    openWindows = [];
    nextWindowId = 1;
    
    hideWinScreen();
    renderDesktop();
    renderTaskbar();
    renderWindows();
    
    showToast("System restarted. Try again!", "info");
}

// ===========================
// EVENT LISTENERS
// ===========================

document.addEventListener('DOMContentLoaded', () => {
    initGame();
    
    document.getElementById('restartBtn').addEventListener('click', restartGame);
    
    document.getElementById('clockIcon').addEventListener('click', () => {
        openApp('clock');
    });
    
    document.getElementById('wifiIcon').addEventListener('click', () => {
        if (!gameState.internetConnected && gameState.wifiEnabled) {
            showToast("Wi-Fi is enabled but not connected to internet.", "info");
        } else if (!gameState.wifiEnabled) {
            showToast("Wi-Fi is currently disabled. Enable it in Settings.", "info");
        } else {
            showToast("Connected to internet!", "success");
        }
    });
});
