const express = require('express');
const session = require('express-session');
const path = require('path');

const app = express();
const PORT = 3000;
const USERNAME = process.env.ADMIN_USER || 'admin';
const PASSWORD = process.env.ADMIN_PASS || 'Admin1234';

app.set('trust proxy', 1);

app.use(express.urlencoded({ extended: true }));
app.use(session({
  secret: process.env.SESSION_SECRET || 'buddy-r-u-live-secret-xZ9k',
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, maxAge: 8 * 60 * 60 * 1000 }
}));

function requireAuth(req, res, next) {
  if (req.session.auth) return next();
  res.redirect('/login');
}

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.get('/', requireAuth, (_req, res) =>
  res.sendFile(path.join(__dirname, 'views/dashboard.html')));

app.get('/login', (req, res) => {
  if (req.session.auth) return res.redirect('/');
  res.sendFile(path.join(__dirname, 'views/login.html'));
});

app.post('/login', (req, res) => {
  const { username, password } = req.body;
  if (username === USERNAME && password === PASSWORD) {
    req.session.auth = true;
    return res.redirect('/');
  }
  res.redirect('/login?error=1');
});

app.post('/logout', (req, res) =>
  req.session.destroy(() => res.redirect('/login')));

app.listen(PORT, () => console.log(`Buddy listening on port ${PORT}`));
