// server.js - minimalny, tylko do testów (nie produkcja)
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
app.use(session({ secret: process.env.SESSION_SECRET || 'dev', resave:false, saveUninitialized:true }));
app.use(express.static(path.join(__dirname, './')));

// Start OAuth: redirect user to GitHub authorize endpoint
app.get('/auth/login', (req, res) => {
  const state = Math.random().toString(36).slice(2);
  req.session.oauth_state = state;
  const url = `https://github.com/login/oauth/authorize?client_id=${GH_CLIENT_ID}&scope=repo&state=${state}`;
  res.redirect(url);
});

// OAuth callback (set redirect URI in GitHub OAuth app to this path)
app.get('/auth/callback', async (req, res) => {
  const { code, state } = req.query;
  if(!code || state !== req.session.oauth_state) return res.status(400).send('Invalid OAuth response');
  // exchange code for access token (server-side, using client_secret)
  const tokenRes = await fetch('https://github.com/login/oauth/access_token', {
    method: 'POST',
    headers: { 'Accept': 'application/json', 'Content-Type':'application/json' },
    body: JSON.stringify({ client_id: GH_CLIENT_ID, client_secret: GH_CLIENT_SECRET, code })
  });
  const tokenJson = await tokenRes.json();
  if(tokenJson.error) return res.status(400).json(tokenJson);
  req.session.token = tokenJson.access_token;
  // fetch user info
  const userRes = await fetch('https://api.github.com/user', { headers:{ 'Authorization':'token '+req.session.token, 'User-Agent':'app' }});
  req.session.user = await userRes.json();
  // redirect back to frontend UI
  res.redirect('/create.html');
});

// endpoint used by frontend to check login
app.get('/api/me', async (req, res) => {
  if(!req.session.token) return res.status(401).json({ error:'not_authenticated' });
  return res.json(req.session.user || { login: 'unknown' });
});

// endpoint do tworzenia repo z template (przykład)
app.post('/api/create-server', async (req, res) => {
  if(!req.session.token) return res.status(401).json({ error:'not_authenticated' });
  const { name, visibility } = req.body;
  // używamy repo-template generate endpoint
  try {
    const url = `https://api.github.com/repos/${TEMPLATE_OWNER}/${TEMPLATE_REPO}/generate`;
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Authorization':'token '+req.session.token, 'Accept':'application/vnd.github+json', 'Content-Type':'application/json' },
      body: JSON.stringify({ name, private: visibility === 'private' })
    });
    const j = await r.json();
    res.status(r.status).json(j);
  } catch(err) {
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, ()=>console.log('listening on', PORT));
