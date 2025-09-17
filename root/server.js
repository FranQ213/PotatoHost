// server.js — minimal but functional (not production hardened)
require('dotenv').config();
const express = require('express');
const session = require('express-session');
const fetch = (...args) => import('node-fetch').then(({default:fetch})=>fetch(...args));
const path = require('path');


const PORT = process.env.PORT || 3000;
const GH_CLIENT_ID = process.env.GH_CLIENT_ID;
const GH_CLIENT_SECRET = process.env.GH_CLIENT_SECRET;
const TEMPLATE_OWNER = process.env.TEMPLATE_OWNER; // owner of template repo
const TEMPLATE_REPO = process.env.TEMPLATE_REPO; // template repo name


if(!GH_CLIENT_ID || !GH_CLIENT_SECRET) {
console.warn('WARNING: set GH_CLIENT_ID and GH_CLIENT_SECRET in .env');
}


const app = express();
app.use(express.json());
app.use(session({secret: process.env.SESSION_SECRET || 'dev-secret', resave:false, saveUninitialized:true, cookie:{secure:false}}));
app.use(express.static(path.join(__dirname, '/'))); // serve index.html and create.html


// 1) Start OAuth flow
app.get('/auth/login', (req, res) => {
const state = Math.random().toString(36).slice(2);
req.session.oauth_state = state;
const redirect = `https://github.com/login/oauth/authorize?client_id=${GH_CLIENT_ID}&scope=repo&state=${state}`;
res.redirect(redirect);
});


// 2) OAuth callback
app.get('/auth/callback', async (req, res) => {
const { code, state } = req.query;
if(!code || state !== req.session.oauth_state) return res.status(400).send('Invalid OAuth callback');


const tokenRes = await fetch('https://github.com/login/oauth/access_token', {
method:'POST',
headers:{'Accept':'application/json','Content-Type':'application/json'},
body: JSON.stringify({client_id: GH_CLIENT_ID, client_secret: GH_CLIENT_SECRET, code})
});
const tokenJson = await tokenRes.json();
if(tokenJson.error){
return res.status(400).json(tokenJson);
}
req.session.token = tokenJson.access_token;


// optional: fetch user info and store login
const userRes = await fetch('https://api.github.com/user', {headers:{'Authorization':'token '+req.session.token,'User-Agent':'node'}});
const userJson = await userRes.json();
req.session.user = {login: userJson.login, id: userJson.id};


// redirect to create UI
res.redirect('/create.html');
});


// 3) return current user
app.get('/api/me', async (req, res) => {
if(!req.session.token) return res.status(401).end();
try{
const r = await fetch('https://api.github.com/user', {headers:{'Authorization':'token '+req.session.token,'User-Agent':'node'}});
const j = await r.json();
res.json(j);
}catch(e){res.status(500).json({error:e.message})}
});


// 4) create repo from template
app.post('/api/create-server', async (req, res) => {
if(!req.session.token) return res.status(401).json({error:'Not authenticated'});
const { name, visibility } = req.body;
if(!name) return res.status(400).json({error:'name required'});


// API: POST /repos/{template_owner}/{template_repo}/generate
const apiUrl = `https://api.github.com/repos/${TEMPLATE_OWNER}/${TEMPLATE_REPO}/generate`;
const payload = {
name,
