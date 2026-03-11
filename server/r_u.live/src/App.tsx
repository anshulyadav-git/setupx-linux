import './App.css'

const DOMAIN = 'r-u.live'

const services = [
  {
    name: 'Website',
    url: `https://${DOMAIN}`,
    icon: '🌐',
    desc: 'This site',
    color: '#6366f1',
  },
  {
    name: 'Supabase Studio',
    url: `https://supabase.${DOMAIN}`,
    icon: '🗄️',
    desc: 'Database & Auth UI',
    color: '#3ecf8e',
  },
  {
    name: 'Supabase API',
    url: `https://api.${DOMAIN}`,
    icon: '⚡',
    desc: 'REST & Realtime API',
    color: '#3ecf8e',
  },
  {
    name: 'Coolify',
    url: `https://coolify.${DOMAIN}`,
    icon: '🚀',
    desc: 'Deployment dashboard',
    color: '#6c47ff',
  },
  {
    name: 'Mail',
    url: `https://mail.${DOMAIN}`,
    icon: '✉️',
    desc: 'Webmail interface',
    color: '#f59e0b',
  },
]

const stack = [
  { label: 'React + Vite', icon: '⚛️' },
  { label: 'Nginx', icon: '🔀' },
  { label: 'PostgreSQL', icon: '🐘' },
  { label: 'Supabase', icon: '🗄️' },
  { label: 'Coolify', icon: '🚀' },
  { label: 'Docker', icon: '🐳' },
  { label: 'Cloudflare', icon: '🌩️' },
  { label: "Let's Encrypt", icon: '🔒' },
]

export default function App() {
  return (
    <div className="page">
      {/* Hero */}
      <header className="hero">
        <div className="hero-badge">Self-hosted infrastructure</div>
        <h1 className="hero-title">
          <span className="accent">r-u</span>.live
        </h1>
        <p className="hero-sub">
          A fully self-hosted stack running on a single Linux server —
          database, deployments, mail, and more.
        </p>
      </header>

      {/* Services grid */}
      <section className="section">
        <h2 className="section-title">Services</h2>
        <div className="grid">
          {services.map((s) => (
            <a
              key={s.name}
              href={s.url}
              target="_blank"
              rel="noopener noreferrer"
              className="card"
              style={{ '--accent': s.color } as React.CSSProperties}
            >
              <div className="card-icon">{s.icon}</div>
              <div className="card-body">
                <div className="card-name">{s.name}</div>
                <div className="card-desc">{s.desc}</div>
                <div className="card-url">{s.url.replace('https://', '')}</div>
              </div>
              <div className="card-arrow">→</div>
            </a>
          ))}
        </div>
      </section>

      {/* Stack pills */}
      <section className="section">
        <h2 className="section-title">Stack</h2>
        <div className="pills">
          {stack.map((t) => (
            <span key={t.label} className="pill">
              {t.icon} {t.label}
            </span>
          ))}
        </div>
      </section>

      <footer className="footer">
        <span>© {new Date().getFullYear()} {DOMAIN}</span>
        <span className="sep">·</span>
        <span>Secured by Cloudflare &amp; Let's Encrypt</span>
      </footer>
    </div>
  )
}
