var appname = 'Malíček';
var color = '#000000';
var nick = null;
var room = null;
var last = null;
var interval = 3;
var intervalref = null;
var keepalive = 900;
var keepaliveref = null;
var timeout = 5000;
var usermap = {};
var notifications = 0;
var sound = true;
var playgames = false;
var status = 15;
var statusref = null

var smileys = {
    '[:-)]': 'https://o00o.cz/2008/o/ikony/s_24.gif',
    '[:->]': 'https://o00o.cz/2008/o/ikony/s_25.gif',
    '[:-D]': 'https://o00o.cz/2008/o/ikony/s_16.gif',
    '[;-D]': 'https://o00o.cz/2008/o/ikony/s_17.gif',
    '[;-)]': 'https://o00o.cz/2008/o/ikony/s_11.gif',
    '[:-|]': 'https://o00o.cz/2008/o/ikony/s_09.gif',
    '[:-o]': 'https://o00o.cz/2008/o/ikony/s_15.gif',
    '[8-o]': 'https://o00o.cz/2008/o/ikony/s_13.gif',
    '[:-(]': 'https://o00o.cz/2008/o/ikony/s_07.gif',
    '[:-E]': 'https://o00o.cz/2008/o/ikony/s_06.gif',
    '[;-(]': 'https://o00o.cz/2008/o/ikony/s_58.gif',
    '[:-c]': 'https://o00o.cz/2008/o/ikony/s_08.gif',
    '[:-Q]': 'https://o00o.cz/2008/o/ikony/s_12.gif',
    '[:-3]': 'https://o00o.cz/2008/o/ikony/s_14.gif',
    '[:-$]': 'https://o00o.cz/2008/o/ikony/s_18.gif',
    '[O:-)]': 'https://o00o.cz/2008/o/ikony/s_19.gif',
    '[]:-)]': 'https://o00o.cz/2008/o/ikony/s_20.gif',
    '[Z]': 'https://o00o.cz/2008/o/ikony/s_10.gif',
    '[?]': 'https://o00o.cz/2008/o/ikony/s_21.gif',
    '[!]': 'https://o00o.cz/2008/o/ikony/s_05.gif',
    '[R^]': 'https://o00o.cz/2008/o/ikony/s_22.gif',
    '[Rv]': 'https://o00o.cz/2008/o/ikony/s_23.gif',
    '[O=]': 'https://o00o.cz/2008/o/ikony/s_26.gif',
    '[@)->-]': 'https://o00o.cz/2008/o/ikony/s_27.gif',
    '[*O]': 'https://o00o.cz/2008/o/ikony/s_28.gif',
    '[8=]': 'https://o00o.cz/2008/o/ikony/s_29.gif',
    '[$>]': 'https://o00o.cz/2008/o/ikony/s_30.gif'
};

function encodeentities(txt) {
    txt = txt.replace(new RegExp('&', 'g'), '&amp;');
    txt = txt.replace(new RegExp('<', 'g'), '&lt;');
    txt = txt.replace(new RegExp('>', 'g'), '&gt;');
    txt = txt.replace(new RegExp('"', 'g'), '&quot;');
    return txt;
}

function metaquote(txt) {
    txt = txt.replace(new RegExp('(\\[|\\]|\\(|\\)|\\^|\\$|\\||\\*|\\?)', 'g'), '\\$1');
    return txt;
}

function fixmessage(message) {
    message = encodeentities(message);
    message = message.replace(new RegExp('(https?:\\/\\/[^ \\[$]*)', 'g'),
                              '<a href="$1" target="_blank" rel="noopener noreferer">$1</a>');
    for (var key in smileys) {
        message = message.replace(new RegExp(metaquote(encodeentities(key)), 'g'),
            '<img src="' + smileys[key] 
            + '" class="smiley" alt="' + encodeentities(key) + '">');
    }
    return message;
}

function setmode(mode) {
    var spinner = document.getElementById('spinner');
    var chat = document.getElementById('chat');
    var login = document.getElementById('login');
    var input = document.getElementById('input');
    spinner.style.display = 'none';
    chat.style.display = 'none';
    login.style.display = 'none';
    input.style.display = 'none';
    switch (mode) {
        case 'spinner':
            spinner.style.display = 'block';
            break;
        case 'login':
            login.style.display = 'block';
            break;
        case 'chat':
            chat.style.display = 'block';
            input.style.display = 'block';
            break;
        case 'rooms':
            chat.style.display = 'block';
            break;
        default:
            alert('Uknown mode selected!');
    }
}

function togglemenu(ev, mode) {
    var menu = document.getElementById('menu');
    if (mode === true) {
        menu.style.display = 'block';
    } else if (mode === false) {
        menu.style.display = 'none';
    } else {
        if (menu.style.display === 'block') {
            menu.style.display = 'none';
        } else {
            menu.style.display = 'block';
        }
    }
}

function togglesound(ev, mode) {
    var toggle = document.getElementById('soundtoggle');
    if (mode === true) {
        sound = true;
        toggle.textContent = '🔔';
    } else if (mode === false) {
        sound = false;
        toggle.textContent = '🔕';
    } else {
        togglesound(null, sound === true ? false : true);
    }
}

function togglesmileys(ev, mode) {
    var selector = document.getElementById('smileyselector');
    if (mode === true) {
        selector.style.display = 'block';
    } else if (mode === false) {
        selector.style.display = 'none';
    } else {
        togglesmileys(null, selector.style.display === 'block' ? false : true);
    }
}

function checkstatus() {
    var rm = new XMLHttpRequest();
    var rf = new XMLHttpRequest();
    rm.timeout = timeout;
    rf.timeout = timeout;
    rm.onreadystatechange = function() {
        if (this.readyState !== 4) {
            return false;
        }
        if (this.status === 200) {
            var res = JSON.parse(this.response);
            if (res.mail) {
                document.getElementById('mailnotification').style.display = 'inline-block';
            }
        }
    };
    rf.onreadystatechange = function() {
        if (this.readyState !== 4) {
            return false;
        }
        if (this.status === 200) {
            var res = JSON.parse(this.response);
            if (res.active) {
                document.getElementById('fridgenotification').style.display = 'inline-block';
            }
        }
    };
    rm.open('GET', '/api/status');
    rf.open('GET', '/api/games/lednicka');
    if (document.getElementById('mailnotification').style.display !== 'inline-block') {
        rm.send();
    }
    if (document.getElementById('fridgenotification').style.display !== 'inline-block') {
        rf.send();
    }
}

function readmail() {
    window.open('https://www.alik.cz/@', '_blank');
    document.getElementById('mailnotification').style.display = 'none';
}

function playfridge() {
    var r = new XMLHttpRequest();
    r.onreadystatechange = function() {
        if (this.readyState === 4) {
            document.getElementById('fridgenotification').style.display = 'none';
        }
    }
    r.timeout = timeout;
    r.open('POST', '/api/games/lednicka');
    r.send();
}

function scrolltobottom() {
    if (!room) {
        return false;
    }
    window.scroll(0, document.body.scrollHeight);
}

function submit() {
    if (!room) {
        return false;
    }
    var to = null;
    if (document.getElementById('entry').value.substr(0, 1) === '@') {
        to = document.getElementById('entry').value.substr(1).split(':')[0];
        if (usermap[to]) {
            document.getElementById('entry').value =
                document.getElementById('entry').value.substr(to.length + 2);
            to = usermap[to];
        } else {
            to = null;
        }
    } else {
        to = 0;
    }
    if (to !== null) {
        var r = new XMLHttpRequest();
        r.open('POST', '/api/rooms/' + room);
        r.onreadystatechange = function() {
            if (this.readyState !== 4) {
                return false;
            }
            chat();
        };
        r.timeout = timeout;
        r.setRequestHeader('Content-Type', 'application/json');
        r.send(JSON.stringify({
            action: 'post',
            to: to,
            color: color,
            message: document.getElementById('entry').value
        }));
        document.getElementById('entry').value = '';
    }
    return false;
}

function noop() {
    if (!room) {
        return false;
    }
    var r = new XMLHttpRequest();
    r.open('POST', '/api/rooms/' + room);
    r.timeout = timeout;
    r.setRequestHeader('Content-Type', 'application/json');
    r.send(JSON.stringify({
        action: 'post',
        to: -1,
        color: color,
        message: '[malíček - keep-alive message - ' + Math.random() + ']'
    }));
}

function setrecipient(recipient) {
    var entry = document.getElementById('entry');
    if (entry.value.indexOf(recipient + ': ') === 0) {
        entry.value = '@' + entry.value;
    } else if (entry.value.indexOf('@' + recipient + ': ') === 0) {
        entry.value = entry.value.substr(1);
    } else {
        entry.value = recipient + ': ' + entry.value;
    }
    document.getElementById('entry').focus();
}

function notify() {
    if (notifications) {
        if ("vibrate" in navigator) {
            window.navigator.vibrate(500);
        }
        if (sound) {
            document.getElementById('alarm').play();
        }
    } else {
        return false;
    }
}

function bubble(message, doscroll) {
    var buffer = document.getElementById('buffer');
    var bubble = document.createElement('div');
    var text = document.createElement('div');
    var alarm = null;
    if (message.type === 'system') {
        bubble.className = 'system';
        if (message.time) {
            var time = document.createElement('div');
            time.className = 'system-time';
            time.appendChild(document.createTextNode(message.time));
            bubble.appendChild(time);
        }
        bubble.appendChild(document.createTextNode(message.message));
    } else {
        var header = document.createElement('div');
        var author = document.createElement('div');
        var time = document.createElement('div');
        bubble.className = 'bubble';
        if (message.nick === nick) {
            bubble.className += ' my-message';
        } else {
            bubble.className += ' message';
        }
        if (message.color) {
            bubble.style.background = message.color;
        }
        header.className = 'bubble-header';
        author.className = 'bubble-author';
        author.appendChild(document.createTextNode(message.nick));
        time.className = 'bubble-time';
        header.appendChild(author);
        if (message.private.length) {
            bubble.className += ' private';
            bubble.style.background = 'inherit';
            if (message.color) {
                bubble.style.color = message.color;
                bubble.style.borderColor = message.color;
            }
            var recipient = document.createElement('div');
            recipient.className = 'bubble-recipient';
            recipient.appendChild(document.createTextNode(message.private[0]));
            header.appendChild(recipient);
            if (message.private[0] === nick) {
                alarm = 1;
            }
        }
        if (message.time) {
            time.appendChild(document.createTextNode(message.time));
            header.appendChild(time);
        }
        if (message.message.toLowerCase().indexOf(nick.toLowerCase()) !== -1) {
            alarm = 1;
        }
        if (message.avatar) {
            avatar = document.createElement('div');
            avatar.className = 'avatar';
            avatar.style.backgroundImage = 'url(' + message.avatar + ')';
            if (message.private.length) {
                avatar.style.borderColor = message.color;
            }
            bubble.appendChild(avatar);
            text.style.marginLeft = '3.8em';
        }
        bubble.appendChild(header);
        text.className = 'bubble-text';
        text.innerHTML = fixmessage(message.message);
        bubble.appendChild(text);
        bubble.addEventListener('click', function() {
            if (message.private.length) {
                if (message.nick === nick) {
                    setrecipient(message.private[0]);
                    return true;
                }
            }
            setrecipient(message.nick)
        });
    }
    var shouldscroll = doscroll;
    if ((document.body.scrollHeight - (window.innerHeight / 4))
        <= (window.innerHeight + window.pageYOffset)) {
        shouldscroll = true;
    }
    buffer.appendChild(bubble);
    if (shouldscroll) {
        scrolltobottom();
    }
    if (alarm) {
        bubble.className += ' notify';
        notify();
    }
}

function rooms() {
    var r = new XMLHttpRequest();
    r.onreadystatechange = function() {
        if (this.readyState === 4) {
            if (this.status === 502 || this.status === 401) {
                logout();
            }
            if (this.status === 200) {
                document.getElementById('buffer').textContent = '';
                var res = JSON.parse(this.response);
                for (var i in res) {
                    var node = document.createElement('div');
                    var name = document.createElement('div');
                    var users = document.createElement('ul');
                    name.appendChild(document.createTextNode(res[i].name));
                    node.id = 'room-' + res[i].id;
                    node.className = 'room-item';
                    if (res[i].id) {
                        node.addEventListener('click', function() {
                            room = this.id.substr(5);
                            document.getElementById('statusline').textContent = this.childNodes[0].textContent;
                            document.getElementById('statusline').textContent += ' | ' + appname;
                            document.title = document.getElementById('statusline').textContent;
                            document.getElementById('buffer').textContent = '';
                            document.getElementById('input').style.display = 'block';
                            notifications = 0;
                            chat(true);
                            setup();
                            scrolltobottom();
                            window.setTimeout(function() { notifications = 1 }, timeout);
                        });
                    } else {
                        node.className += ' room-unavailable';
                    }
                    name.className = 'room-name';
                    node.appendChild(name);
                    if (res[i].allowed !== 'all') {
                        name.className += ' locked';
                        var lock = document.createElement('div');
                        var lockmsg;
                        lock.className = 'room-lock';
                        if (res[i].allowed === 'boys') {
                            lockmsg = 'K tomuto stolu smí přisednout jen kluci.';
                        } else if (res[i].allowed === 'girls') {
                            lockmsg = 'K tomuto stolu smí přisednout jen holky.';
                        } else if (res[i].allowed === 'friends') {
                            lockmsg = 'K tomuto stolu smí přisednout jen kamarádi.';
                        } else {
                            lockmsg = 'K tomuto stolu nesmí přisednout nikdo.';
                        }
                        lock.appendChild(document.createTextNode(lockmsg));
                        node.appendChild(lock);
                    }
                    users.className = 'room-users';
                    if (res[i].users.length) {
                        for (var u in res[i].users) {
                            var li = document.createElement('li');
                            switch (res[i].users[u].sex) {
                                case 'boy':
                                    li.className = 'room-user-boy';
                                    break;
                                case 'girl':
                                    li.className = 'room-user-girl';
                                    break;
                                default:
                                    li.className = 'room-user-unisex';
                            }
                            if (res[i].users[u].admin.length) {
                                li.className = li.className + ' room-user-admin';
                            }
                            li.appendChild(document.createTextNode(res[i].users[u].name));
                            users.appendChild(li);
                        }
                    } else {
                        var info = document.createElement('div');
                        info.className = 'room-info';
                        info.appendChild(document.createTextNode('U tohoto stolu nikdo nesedí.'));
                        node.appendChild(info);
                    }
                    node.appendChild(users);
                    document.getElementById('buffer').appendChild(node);
                }
            } else {
                logout();
            }
        }
    };
    r.timeout = timeout;
    r.open('GET', '/api/rooms');
    r.send();
}

function setup() {
    if (!room) {
        return false;
    }
    r = new XMLHttpRequest();
    r.onreadystatechange = function() {
        if (this.readyState !== 4) {
            return false;
        }
        if (this.status !== 200 || !this.response) {
            return false;
        }
        var res = JSON.parse(this.response);
        color = res.color;
        if (res.refresh >= 3) {
            interval = res.refresh;
        } else {
            interval = 3;
        }
        intervalref = window.setInterval(chat, interval * 1000);
        keepaliveref = window.setInterval(noop, keepalive * 1000);
        document.getElementById('status').style.background = color;
        document.getElementById('input').style.background = color;
        document.querySelector('meta[name=theme-color]').setAttribute('content', color);
    };
    r.timeout = timeout;
    r.open('GET', '/api/rooms/' + room + '?query=settings', true);
    r.send();
}

function chat(doscroll) {
    if (!room) {
        return false;
    }
    r = new XMLHttpRequest();
    r.onreadystatechange = function() {
        if (this.readyState !== 4) {
            return false;
        }
        if (this.status === 502) {
            logout();
        }
        if (this.status === 403) {
            alert('K tomuto stolu si nemůžeš přisednout :(');
            leave();
        }
        if (this.status !== 200 || !this.response) {
            return false;
        }
        var chat = JSON.parse(this.response);
        var messages = chat.messages;
        var users = chat.users;
        var index = -1;
        if (last === null) {
            index = messages.length - 1;
        } else {
            for (var i in messages) {
                if (last.nick === messages[i].nick
                    && last.message === messages[i].message
                    && last.private.length == messages[i].private.length
                    && last.private.sort().every(function(val, idx) {
                        return val === messages[i].private.sort()[idx]
                    })) {
                    break;
                }
                index++;
            }
        }
        for (var i = index; i >= 0; i--) {
            bubble(messages[i], doscroll);
        }
        last = {};
        last.nick = messages[0].nick;
        last.message = messages[0].message;
        last.private = messages[0].private.sort();
        usermap = {};
        document.getElementById('users').textContent = '';
        for (var i in users.sort(function(a, b) { return a.link.localeCompare(b.link) })) {
            if (users[i].name !== nick) {
                usermap[users[i].name] = users[i].id;
            }
            usernode = document.createElement('li');
            switch (users[i].sex) {
                case 'boy':
                    usernode.className = 'list-user-boy';
                    break;
                case 'girl':
                    usernode.className = 'list-user-girl';
                    break;
                default:
                    usernode.className = 'list-user-unisex';
            }
            userinfo = document.createElement('span');
            userinfo.className = 'list-user-info';
            if (users[i].age) {
                userinfo.textContent = ' ' + users[i].age + ' let';
            }
            if (users[i].admin.length) {
                var adminstr = '';
                for (var p in users[i].admin) {
                    switch (users[i].admin[p]) {
                        case 'chat':
                            adminstr += '💛';
                            break;
                        case 'rooms':
                            adminstr += '🖤';
                            break;
                        case 'boards':
                            adminstr += '🧡';
                            break;
                        case 'blog':
                            adminstr += '💜';
                            break;
                        case 'master':
                            adminstr += '💚';
                            break;
                        case 'guru':
                            adminstr += '💙';
                            break;
                        default:
                            adminstr += '💔';
                    }
                    adminstr = ' ' + adminstr + ' ';
                }
                userinfo.textContent += adminstr;
            }
            usernode.appendChild(document.createTextNode(users[i].name));
            usernode.appendChild(userinfo);
            usernode.addEventListener('click', function() {
                setrecipient(this.childNodes[0].textContent);
            });
            document.getElementById('users').appendChild(usernode);
        }
    };
    r.timeout = timeout;
    r.open('GET', '/api/rooms/' + room);
    r.send();
}

function leave(ev, mode) {
    if (!room) {
        return false;
    }
    setmode('spinner');
    window.clearInterval(intervalref);
    window.clearInterval(keepaliveref);
    document.getElementById('buffer').textContent = '';
    togglemenu(null, false);
    usermap = {};
    document.getElementById('users').textContent = '';
    var r = new XMLHttpRequest();
    r.onreadystatechange = function() {
        if (this.readyState === 4) {
            document.getElementById('statusline').textContent = appname;
            document.title = appname;
            room = null;
            if (mode !== 'logout') {
                setmode('rooms');
                rooms();
            }
        }
    };
    r.open('POST', '/api/rooms/' + room, false);
    r.setRequestHeader('Content-Type', 'application/json');
    r.send(JSON.stringify({
        action: 'leave'
    }));
}

function login() {
    var r = new XMLHttpRequest();
    document.getElementById('username').disabled = true;
    document.getElementById('password').disabled = true;
    setmode('spinner');
    r.onreadystatechange = function() {
        if (this.readyState === 4) {
            if (this.status === 200) {
                nick = document.getElementById('username').value;
                document.cookie = 'nick=' + nick;
                document.getElementById('username').disabled = false;
                document.getElementById('password').disabled = false;
                setmode('rooms');
                rooms();
            } else {
                document.getElementById('username').disabled = false;
                document.getElementById('password').disabled = false;
                setmode('login');
            }
            document.getElementById('password').value = '';
        }
    }
    r.open('POST', '/api/login', false);
    r.setRequestHeader('Content-Type', 'application/json');
    r.send(JSON.stringify({
        user: document.getElementById('username').value,
        pass: document.getElementById('password').value
    }));
}

function logout() {
    togglemenu(null, false);
    document.getElementById('buffer').textContent = '';
    setmode('spinner');
    if (room) {
        leave(null, 'logout');
    }
    var r = new XMLHttpRequest();
    r.onreadystatechange = function() {
        if (this.readyState === 4) {
            setmode('login');
        }
    };
    r.open('GET', '/api/logout', false);
    r.send();
}

function reconcile() {
    var r = new XMLHttpRequest();
    r.onreadystatechange = function() {
        if (this.readyState === 4) {
            if (this.status === 200) {
                setmode('rooms');
                rooms();
            } else {
                room = null;
                last = null;
                setmode('login');
            }
        }
    };
    r.open('GET', '/api/', false);
    r.send();
}

function init() {
    document.getElementById('menutoggle').addEventListener('click', togglemenu);
    document.getElementById('soundtoggle').addEventListener('click', togglesound);
    document.getElementById('smileys').addEventListener('click', togglesmileys);
    for (var s in smileys) {
        var smiley = document.createElement('div');
        smiley.style.backgroundImage = 'url(' + smileys[s] + ')';
        smiley.myData = s;
        smiley.addEventListener('click', function() {
            document.getElementById('entry').value += this.myData;
        });
        document.getElementById('smileyselector').appendChild(smiley);
    }
    document.getElementById('mailnotification').addEventListener('click', readmail);
    document.getElementById('fridgenotification').addEventListener('click', playfridge);
    statusref = window.setInterval(checkstatus, status * 1000);
    document.getElementById('leave').addEventListener('click', leave);
    document.getElementById('logout').addEventListener('click', logout);
    document.getElementById('loginform').addEventListener('submit', login);
    document.getElementById('inputform').addEventListener('submit', submit);
    window.addEventListener('resize', scrolltobottom);
    var cookies = decodeURIComponent(document.cookie).split(';');
    for (var i in cookies) {
        var cookie = cookies[i];
        while (cookie.charAt(0) === ' ') {
            cookie = cookie.substr(1);
        }
        if (cookie.indexOf('nick=') === 0) {
            nick = cookie.substr(5);
        }
    }
    reconcile();
}

window.addEventListener('DOMContentLoaded', init);
