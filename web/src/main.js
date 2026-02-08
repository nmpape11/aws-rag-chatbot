let API_URL = "";

// 1. Load config on startup
async function init() {
    try {
        const res = await fetch('./config.json');
        const config = await res.json();
        API_URL = config.apiUrl;
        document.getElementById('status').innerText = "API Connected";
    } catch (err) {
        document.getElementById('status').innerText = "Config Error";
        console.error("Could not load config.json", err);
    }
}

const chatWindow = document.getElementById('chat-window');
const chatForm = document.getElementById('chat-form');

function appendMessage(role, text) {
    const msg = document.createElement('div');
    msg.className = role === 'user' 
        ? "bg-slate-200 p-3 rounded-lg max-w-[80%] ml-auto text-slate-800" 
        : "bg-blue-100 p-3 rounded-lg max-w-[80%] text-blue-900";
    msg.innerText = text;
    chatWindow.appendChild(msg);
    chatWindow.scrollTop = chatWindow.scrollHeight;
}

chatForm.onsubmit = async (e) => {
    e.preventDefault();
    const input = document.getElementById('user-input');
    const text = input.value.trim();
    if (!text || !API_URL) return;

    appendMessage('user', text);
    input.value = "";

    try {
        const response = await fetch(API_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ q: text })
        });
        const data = await response.json();
        appendMessage('bot', data.answer || data.message || JSON.stringify(data));
    } catch (err) {
        appendMessage('bot', "Error: Could not reach the API.");
    }
};

init();