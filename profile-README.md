<!--==================================================================
  MANIKARAJ ANBURAJ  ·  @manikkDev
  Cyberpunk / Neon profile README
  Self-contained animated SVGs (no external JS) — renders on GitHub.
===================================================================-->

<!-- ============================ HEADER ============================ -->
<!-- Inline animated neon header SVG (self-contained, always renders on GitHub) -->
<p align="center">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 880 220" width="100%" style="max-width:880px;background:radial-gradient(circle at 50% 50%, #0a0a12 0%, #05050a 100%);border-radius:14px">
  <defs>
    <linearGradient id="neonGrad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#ff2e63"/>
      <stop offset="45%" stop-color="#b537f2"/>
      <stop offset="100%" stop-color="#00f0ff"/>
    </linearGradient>
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0a0a12"/>
      <stop offset="100%" stop-color="#05050a"/>
    </linearGradient>
    <filter id="neonGlow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="3.5" result="b1"/>
      <feGaussianBlur stdDeviation="7" result="b2"/>
      <feMerge>
        <feMergeNode in="b2"/>
        <feMergeNode in="b1"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
    <filter id="softGlow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="2" result="b"/>
      <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <style>
    .title  { font: 800 58px "Segoe UI",system-ui,sans-serif; letter-spacing:2px; fill:url(#neonGrad); filter:url(#neonGlow); }
    .sub    { font: 500 18px "Segoe UI",system-ui,sans-serif; letter-spacing:6px; fill:#9ca3ff; filter:url(#softGlow); }
    .tag    { font: 600 13px "Segoe UI",system-ui,sans-serif; letter-spacing:3px; fill:#00f0ff; }
    .pulse  { animation: pulse 2.4s ease-in-out infinite; transform-origin:center; }
    .flicker{ animation: flicker 3.5s linear infinite; }
    .scan   { animation: scan 4s linear infinite; }
    .float1 { animation: float1 6s ease-in-out infinite; }
    .float2 { animation: float2 7s ease-in-out infinite; }
    .float3 { animation: float3 8s ease-in-out infinite; }
    .dash   { stroke-dasharray: 880; stroke-dashoffset: 880; animation: draw 3s ease forwards infinite alternate; }
    @keyframes pulse   { 0%,100%{opacity:1} 50%{opacity:.55} }
    @keyframes flicker { 0%,19%,21%,23%,80%,100%{opacity:1} 20%,22%{opacity:.4} 81%{opacity:.7} }
    @keyframes scan    { 0%{transform:translateY(0)} 100%{transform:translateY(220px)} }
    @keyframes float1  { 0%,100%{transform:translate(0,0)} 50%{transform:translate(8px,-10px)} }
    @keyframes float2  { 0%,100%{transform:translate(0,0)} 50%{transform:translate(-10px,8px)} }
    @keyframes float3  { 0%,100%{transform:translate(0,0)} 50%{transform:translate(6px,12px)} }
    @keyframes draw    { to{stroke-dashoffset:0} }
    @media (prefers-reduced-motion: reduce){ *{animation:none!important} }
  </style>

  <rect width="880" height="220" fill="url(#bgGrad)" rx="14"/>
  <!-- grid -->
  <g stroke="#1a1a2e" stroke-width="1" opacity="0.5">
    <path d="M0 40 H880 M0 80 H880 M0 120 H880 M0 160 H880 M0 200 H880"/>
    <path d="M80 0 V220 M180 0 V220 M280 0 V220 M380 0 V220 M480 0 V220 M580 0 V220 M680 0 V220 M780 0 V220"/>
  </g>
  <!-- floating particles -->
  <circle class="float1" cx="120" cy="60"  r="2.5" fill="#ff2e63" filter="url(#softGlow)"/>
  <circle class="float2" cx="760" cy="70"  r="2"   fill="#00f0ff" filter="url(#softGlow)"/>
  <circle class="float3" cx="200" cy="170" r="2"   fill="#b537f2" filter="url(#softGlow)"/>
  <circle class="float1" cx="700" cy="160" r="2.5" fill="#00f0ff" filter="url(#softGlow)"/>
  <circle class="float2" cx="430" cy="40"  r="1.8" fill="#ff2e63" filter="url(#softGlow)"/>
  <!-- scanline -->
  <rect class="scan" x="0" y="0" width="880" height="2" fill="#00f0ff" opacity="0.12"/>
  <!-- animated underline -->
  <line class="dash" x1="120" y1="150" x2="760" y2="150" stroke="url(#neonGrad)" stroke-width="2" filter="url(#softGlow)"/>
  <!-- title -->
  <text class="title flicker" x="440" y="105" text-anchor="middle">MANIKARAJ ANBURAJ</text>
  <text class="sub"   x="440" y="138" text-anchor="middle">GAME&nbsp;DEVELOPER&nbsp;//&nbsp;FULL-STACK&nbsp;ENGINEER</text>
  <text class="tag pulse" x="440" y="190" text-anchor="middle">&lt;&nbsp;building&nbsp;imaginary&nbsp;worlds&nbsp;/&gt;</text>
</svg>
</p>

<!-- ============================ STATUS BAR ============================ -->
<p align="center">
  <img src="https://img.shields.io/badge/STATUS-ONLINE-00f0ff?style=for-the-badge&labelColor=0a0a12&color=00f0ff" alt="status"/>
  <img src="https://img.shields.io/badge/FOCUS-RPG%20%7C%20ROBLOX%20%7C%20UNREAL-ff2e63?style=for-the-badge&labelColor=0a0a12&color=ff2e63" alt="focus"/>
  <img src="https://img.shields.io/badge/STACK-FULL--STACK-b537f2?style=for-the-badge&labelColor=0a0a12&color=b537f2" alt="stack"/>
  <img src="https://img.shields.io/badge/AVAILABILITY-OPEN%20TO%20COLLAB-39ff14?style=for-the-badge&labelColor=0a0a12&color=39ff14" alt="availability"/>
</p>

<hr style="border:0;border-top:1px solid #1a1a2e;margin:18px 0">

<!-- ============================ TYPEWRITER QUOTE ============================ -->
<p align="center">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 90" width="100%" style="max-width:720px;background:#07070d;border-radius:10px;border:1px solid #1a1a2e">
  <style>
    .tw   { font: 500 19px "Segoe UI",system-ui,sans-serif; fill:#00f0ff; }
    .cur  { font: 500 19px "Segoe UI",system-ui,sans-serif; fill:#ff2e63; animation: blink 0.9s step-end infinite; }
    .qbar { fill:#0d0d18; }
    @keyframes blink { 0%,100%{opacity:1} 50%{opacity:0} }
  </style>
  <rect class="qbar" width="720" height="90" rx="10"/>
  <text x="30" y="40" fill="#b537f2" font="600 14px 'Segoe UI'" letter-spacing="2">// philosophy.dat</text>
  <text class="tw" x="30" y="68">I code games to bring imaginary worlds to life</text>
  <text class="cur" x="565" y="68">_</text>
</svg>
</p>

<!-- ============================ ABOUT ============================ -->
<h2 align="center">
  <img src="https://img.shields.io/badge/%E2%95%91%20ABOUT%20ME%20%E2%95%91-0a0a12?style=for-the-badge&labelColor=0a0a12&color=b537f2"/>
</h2>

<table align="center" style="border:none;max-width:760px">
  <tr>
    <td align="left" style="border:none;padding:14px 18px;background:#07070d;border:1px solid #1a1a2e;border-radius:10px">

<!-- Animated neon-border card -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 30" width="100%" style="max-width:720px;margin-bottom:8px">
  <defs>
    <linearGradient id="ab" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#ff2e63"/><stop offset="50%" stop-color="#b537f2"/><stop offset="100%" stop-color="#00f0ff"/>
    </linearGradient>
  </defs>
  <style>.ln{stroke:url(#ab);stroke-width:2;stroke-dasharray:720;stroke-dashoffset:720;animation:dw 4s ease forwards infinite alternate}@keyframes dw{to{stroke-dashoffset:0}}</style>
  <line class="ln" x1="10" y1="15" x2="710" y2="15"/>
</svg>

```text
> whoami
manik  ·  manikaraj anburaj  ·  @manikkDev

> role
game developer  //  full-stack web engineer  //  tech enthusiast

> location
india  ·  remote-friendly  ·  always-on terminal

> current_mission
crafting an RPG across Roblox Studio + Unreal Engine,
shipping full-stack web projects, and exploring Unreal's stack.

> specialties
real-time systems  ·  gameplay scripting  ·  UI/UX  ·  backend APIs
```

<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 30" width="100%" style="max-width:720px;margin-top:8px">
  <defs><linearGradient id="ab2" x1="0%" y1="0%" x2="100%" y2="0%"><stop offset="0%" stop-color="#00f0ff"/><stop offset="50%" stop-color="#b537f2"/><stop offset="100%" stop-color="#ff2e63"/></linearGradient></defs>
  <style>.ln2{stroke:url(#ab2);stroke-width:2;stroke-dasharray:720;stroke-dashoffset:720;animation:dw2 4s ease forwards infinite alternate}@keyframes dw2{to{stroke-dashoffset:0}}</style>
  <line class="ln2" x1="10" y1="15" x2="710" y2="15"/>
</svg>

    </td>

  </tr>
</table>

<!-- ============================ TECH ARSENAL ============================ -->
<h2 align="center">
  <img src="https://img.shields.io/badge/%E2%95%91%20TECH%20ARSENAL%20%E2%95%91-0a0a12?style=for-the-badge&labelColor=0a0a12&color=00f0ff"/>
</h2>

<!-- Animated marquee of tech names -->
<p align="center">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 40" width="100%" style="max-width:720px;background:#07070d;border-radius:8px;border:1px solid #1a1a2e">
  <defs>
    <linearGradient id="mq" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#ff2e63"/><stop offset="50%" stop-color="#b537f2"/><stop offset="100%" stop-color="#00f0ff"/>
    </linearGradient>
  </defs>
  <style>
    .mtext { font: 700 16px "Segoe UI",system-ui,sans-serif; fill:url(#mq); white-space:nowrap; }
    .marq  { animation: marq 18s linear infinite; }
    @keyframes marq { 0%{transform:translateX(720px)} 100%{transform:translateX(-720px)} }
  </style>
  <g class="marq">
    <text class="mtext" x="0" y="26">JAVASCRIPT  ·  TYPESCRIPT  ·  REACT  ·  NODE.JS  ·  HTML5  ·  CSS3  ·  C++  ·  C#  ·  LUA  ·  LUau  ·  UNITY  ·  UNREAL ENGINE  ·  ROBLOX STUDIO  ·  PYTHON  ·  GIT  ·  </text>
    <text class="mtext" x="720" y="26">JAVASCRIPT  ·  TYPESCRIPT  ·  REACT  ·  NODE.JS  ·  HTML5  ·  CSS3  ·  C++  ·  C#  ·  LUA  ·  LUau  ·  UNITY  ·  UNREAL ENGINE  ·  ROBLOX STUDIO  ·  PYTHON  ·  GIT  ·  </text>
  </g>
</svg>
</p>

<h3 align="center">Languages &amp; Frameworks</h3>
<p align="center">
  <img src="https://img.shields.io/badge/JavaScript-F7DF1E?style=for-the-badge&logo=javascript&logoColor=black&labelColor=0a0a12" alt="js"/>
  <img src="https://img.shields.io/badge/TypeScript-3178C6?style=for-the-badge&logo=typescript&logoColor=white&labelColor=0a0a12" alt="ts"/>
  <img src="https://img.shields.io/badge/React-61DAFB?style=for-the-badge&logo=react&logoColor=black&labelColor=0a0a12" alt="react"/>
  <img src="https://img.shields.io/badge/Node.js-339933?style=for-the-badge&logo=node.js&logoColor=white&labelColor=0a0a12" alt="node"/>
  <br>
  <img src="https://img.shields.io/badge/HTML5-E34F26?style=for-the-badge&logo=html5&logoColor=white&labelColor=0a0a12" alt="html"/>
  <img src="https://img.shields.io/badge/CSS3-1572B6?style=for-the-badge&logo=css3&logoColor=white&labelColor=0a0a12" alt="css"/>
  <img src="https://img.shields.io/badge/C++-00599C?style=for-the-badge&logo=c%2B%2B&logoColor=white&labelColor=0a0a12" alt="cpp"/>
  <img src="https://img.shields.io/badge/C%23-239120?style=for-the-badge&logo=c-sharp&logoColor=white&labelColor=0a0a12" alt="csharp"/>
  <br>
  <img src="https://img.shields.io/badge/Lua-2C2D72?style=for-the-badge&logo=lua&logoColor=white&labelColor=0a0a12" alt="lua"/>
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white&labelColor=0a0a12" alt="py"/>
  <img src="https://img.shields.io/badge/Git-F05032?style=for-the-badge&logo=git&logoColor=white&labelColor=0a0a12" alt="git"/>
</p>

<h3 align="center">Game Development</h3>
<p align="center">
  <img src="https://img.shields.io/badge/Unity-000000?style=for-the-badge&logo=unity&logoColor=white&labelColor=0a0a12" alt="unity"/>
  <img src="https://img.shields.io/badge/Unreal%20Engine-313131?style=for-the-badge&logo=unreal-engine&logoColor=white&labelColor=0a0a12" alt="unreal"/>
  <img src="https://img.shields.io/badge/Roblox%20Studio-00A2FF?style=for-the-badge&logo=roblox&logoColor=white&labelColor=0a0a12" alt="roblox"/>
  <img src="https://img.shields.io/badge/Blender-F5792A?style=for-the-badge&logo=blender&logoColor=white&labelColor=0a0a12" alt="blender"/>
</p>

<!-- ============================ CURRENTLY BUILDING ============================ -->
<h2 align="center">
  <img src="https://img.shields.io/badge/%E2%95%91%20CURRENTLY%20BUILDING%20%E2%95%91-0a0a12?style=for-the-badge&labelColor=0a0a12&color=ff2e63"/>
</h2>

<table align="center" style="border:none;max-width:780px">
  <tr>
    <td align="center" width="33%" style="border:none;padding:10px;background:#07070d;border:1px solid #1a1a2e;border-radius:10px">
      <img src="https://img.shields.io/badge/%E2%9A%94-ff2e63?style=flat-square&labelColor=0a0a12&color=ff2e63" alt="rpg"/><br>
      <b style="color:#ff2e63">RPG Game</b><br>
      <sub style="color:#9ca3ff">Roblox Studio + Unreal Engine</sub><br>
      <sub style="color:#6b7280">Real-time combat · progression · world systems</sub>
    </td>
    <td align="center" width="33%" style="border:none;padding:10px;background:#07070d;border:1px solid #1a1a2e;border-radius:10px">
      <img src="https://img.shields.io/badge/%F0%9F%8C%90-00f0ff?style=flat-square&labelColor=0a0a12&color=00f0ff" alt="web"/><br>
      <b style="color:#00f0ff">Full-Stack Web</b><br>
      <sub style="color:#9ca3ff">React · Node · APIs</sub><br>
      <sub style="color:#6b7280">End-to-end products · UI · backend services</sub>
    </td>
    <td align="center" width="33%" style="border:none;padding:10px;background:#07070d;border:1px solid #1a1a2e;border-radius:10px">
      <img src="https://img.shields.io/badge/%F0%9F%A7%AA-b537f2?style=flat-square&labelColor=0a0a12&color=b537f2" alt="unreal"/><br>
      <b style="color:#b537f2">Unreal Engine</b><br>
      <sub style="color:#9ca3ff">Exploring the stack</sub><br>
      <sub style="color:#6b7280">Blueprints · C++ · rendering · gameplay</sub>
    </td>
  </tr>
</table>

<!-- ============================ GITHUB STATS ============================ -->
<h2 align="center">
  <img src="https://img.shields.io/badge/%E2%95%91%20GITHUB%20METRICS%20%E2%95%91-0a0a12?style=for-the-badge&labelColor=0a0a12&color=39ff14"/>
</h2>

<p align="center">
  <img height="170" src="https://github-readme-stats.vercel.app/api?username=manikkDev&show_icons=true&theme=radical&hide_border=true&count_private=true&bg_color=07070d&title_color=00f0ff&icon_color=ff2e63&text_color=9ca3ff" alt="stats"/>
  <img height="170" src="https://github-readme-stats.vercel.app/api/top-langs/?username=manikkDev&layout=compact&theme=radical&hide_border=true&bg_color=07070d&title_color=b537f2&text_color=9ca3ff" alt="top langs"/>
</p>

<p align="center">
  <img height="170" src="https://github-readme-streak-stats.herokuapp.com?user=manikkDev&theme=radical&hide_border=true&background=07070d&ring=ff2e63&fire=b537f2&currStreakLabel=00f0ff&sideLabels=9ca3ff&dates=6b7280" alt="streak"/>
</p>

<!-- Activity graph (neon) -->
<h3 align="center">Contribution Activity</h3>
<p align="center">
  <img src="https://github-readme-activity-graph.vercel.app/graph?username=manikkDev&theme=react-dark&hide_border=true&area=true&color=00f0ff&line=b537f2&point=ff2e63&bg_color=07070d" alt="activity graph" width="100%" style="max-width:820px"/>
</p>

<!-- Trophies -->
<h3 align="center">Trophies</h3>
<p align="center">
  <img src="https://github-profile-trophy.vercel.app/?username=manikkDev&theme=radical&no-frame=true&no-bg=true&column=7&margin-w=8&margin-h=8" alt="trophies" width="100%" style="max-width:820px"/>
</p>

<!-- Profile details cards -->
<details align="center">
  <summary><b style="color:#00f0ff">▸ More profile metrics</b></summary>
  <br>
  <p align="center">
    <img src="https://github-profile-summary-cards.vercel.app/api/cards/profile-details?username=manikkDev&theme=radical" alt="profile details"/>
  </p>
  <p align="center">
    <img src="https://github-profile-summary-cards.vercel.app/api/cards/repos-per-language?username=manikkDev&theme=radical" alt="repos per lang"/>
    <img src="https://github-profile-summary-cards.vercel.app/api/cards/most-commit-language?username=manikkDev&theme=radical" alt="most commit lang"/>
  </p>
  <p align="center">
    <img src="https://github-profile-summary-cards.vercel.app/api/cards/stats?username=manikkDev&theme=radical" alt="stats card"/>
    <img src="https://github-profile-summary-cards.vercel.app/api/cards/productive-time?username=manikkDev&theme=radical&utcOffset=+05:30" alt="productive time"/>
  </p>
</details>

<!-- ============================ SPOTIFY NOW PLAYING ============================ -->
<h2 align="center">
  <img src="https://img.shields.io/badge/%E2%95%91%20NOW%20PLAYING%20%E2%95%91-0a0a12?style=for-the-badge&labelColor=0a0a12&color=1DB954"/>
</h2>

<p align="center">
  <!--
    Live Spotify "now playing" widget.
    Requires deploying novatorem (https://github.com/novatorem/novatorem)
    and linking your Spotify account. Replace the src URL below with
    your deployed instance, e.g. https://your-novatorem.vercel.app/api
  -->
  <img src="https://novatorem.vercel.app/api/spotify-now-playing" alt="Spotify Now Playing" width="420"/>
</p>

<p align="center">
  <sub style="color:#6b7280">Live widget · deploy your own at <a href="https://github.com/novatorem/novatorem">novatorem</a> and update the URL above</sub>
</p>

<!-- ============================ CONNECT ============================ -->
<h2 align="center">
  <img src="https://img.shields.io/badge/%E2%95%91%20CONNECT%20%E2%95%91-0a0a12?style=for-the-badge&labelColor=0a0a12&color=b537f2"/>
</h2>

<p align="center">
  <a href="https://github.com/manikkDev"><img src="https://img.shields.io/badge/GitHub-manikkDev-181717?style=for-the-badge&logo=github&logoColor=white&labelColor=0a0a12" alt="github"/></a>
  <a href="https://www.linkedin.com/in/manikaraj-anburaj-4550ba354"><img src="https://img.shields.io/badge/LinkedIn-Manikaraj%20Anburaj-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white&labelColor=0a0a12" alt="linkedin"/></a>
  <a href="mailto:manikraj8433@gmail.com"><img src="https://img.shields.io/badge/Gmail-manikraj8433-EA4335?style=for-the-badge&logo=gmail&logoColor=white&labelColor=0a0a12" alt="gmail"/></a>
  <a href="https://roblox.com"><img src="https://img.shields.io/badge/Roblox-Studio-00A2FF?style=for-the-badge&logo=roblox&logoColor=white&labelColor=0a0a12" alt="roblox"/></a>
</p>

<!-- ============================ FOOTER ============================ -->
<hr style="border:0;border-top:1px solid #1a1a2e;margin:22px 0">

<p align="center">
  <img src="https://img.shields.io/badge/Built%20with-late%20nights%20%26%20neon-ff2e63?style=flat-square&labelColor=0a0a12&color=b537f2" alt="built with"/>
  <img src="https://visitor-badge.laobi.cn/badge?pageID=manikkDev.manikkDev&left_color=0a0a12&right_color=00f0ff&left_text=visitors" alt="visitors"/>
</p>

<!-- Animated footer divider -->
<p align="center">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 24" width="100%" style="max-width:720px">
  <defs>
    <linearGradient id="ft" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#ff2e63"/><stop offset="50%" stop-color="#b537f2"/><stop offset="100%" stop-color="#00f0ff"/>
    </linearGradient>
  </defs>
  <style>.ftl{stroke:url(#ft);stroke-width:2;stroke-dasharray:720;stroke-dashoffset:720;animation:ftd 5s ease forwards infinite alternate}@keyframes ftd{to{stroke-dashoffset:0}}</style>
  <line class="ftl" x1="10" y1="12" x2="710" y2="12"/>
</svg>
</p>

<p align="center">
  <sub style="color:#6b7280">// end of transmission · <a href="https://github.com/manikkDev">manikkDev</a> · 2024–present</sub>
</p>
