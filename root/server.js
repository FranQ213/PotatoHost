// server.js - minimalny backend do testów (nie produkcja)
require('dotenv').config();
const express = require('express');
const session = require('express-session');
const fetch = (...args) => import('node-fetch').then(m=>m.default(...args));
const path = require('path');

const GH_CLIENT_ID = process.env.GH_CLIENT_ID;
const GH_CLIENT_SECRET = process.env.GH_CLIENT_SECRET;
const TEMPLATE_OWNER = process.env.TEMPLATE_OWNER || '';
const TEMPLATE_REPO = process.env.TEMPLATE_REPO || '';

const app = express();
app.use(express.json());
app.use(session({ secret: process.env.SESSION_SECRET || 'dev-secret', resave:false, saveUninitialized:true }));
app.use(express.static(path.join(__dirname, './')));

// Start OAuth
app.get('/auth/login', (req, res) => {
  const state = Math.random().toString(36).slice(2);
  req.session.oauth_state = state;
  const url = `https://github.com/login/oauth/authorize?client_id=${GH_CLIENT_ID}&scope=repo&state=${state}`;
  res.redirect(url);
});

// Callback
app.get('/auth/callback', async (req, res) => {
  const { code, state } = req.query;
  if(!code || state !== req.session.oauth_state) return res.status(400).send('Invalid OAuth response');
  try {
    const tokenRes = await fetch('https://github.com/login/oauth/access_token', {
      method: 'POST',
      headers: { 'Accept':'application/json','Content-Type':'application/json' },
      body: JSON.stringify({ client_id: GH_CLIENT_ID, client_secret: GH_CLIENT_SECRET, code })
    });
    const tokenJson = await tokenRes.json();
    if(tokenJson.error) return res.status(400).json(tokenJson);
    req.session.token = tokenJson.access_token;

    const userRes = await fetch('https://api.github.com/user', {
      headers: { 'Authorization': 'token ' + req.session.token, 'User-Agent':'potatohost' }
    });
    req.session.user = await userRes.json();

    // redirect to create UI
    res.redirect('/create.html');
  } catch (err) {
    res.status(500).send('OAuth error: ' + err.message);
  }
});

// frontend checks this to know if logged in
app.get('/api/me', (req, res) => {
  if(!req.session.token) return res.status(401).json({ error:'not_authenticated' });
  return res.json(req.session.user || { login: 'unknown' });
});

// create repo from template (example)
app.post('/api/create-server', async (req, res) => {
  if(!req.session.token) return res.status(401).json({ error:'not_authenticated' });
  const { name, visibility } = req.body;
  if(!name) return res.status(400).json({ error:'name required' });
  try {
    const apiUrl = `https://api.github.com/repos/${TEMPLATE_OWNER}/${TEMPLATE_REPO}/generate`;
    const r = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Authorization': 'token ' + req.session.token,
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ name, private: visibility === 'private' })
    });
    const j = await r.json();
    res.status(r.status).json(j);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, ()=>console.log('Server listening on', PORT));
