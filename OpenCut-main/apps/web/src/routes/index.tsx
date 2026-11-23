import { Link, createFileRoute } from '@tanstack/react-router'

export const Route = createFileRoute('/')({ component: Home })

function Home() {
  return (
    <main className="relative min-h-screen overflow-hidden bg-[#f7f7f4] text-[#171717]">
      <div className="pointer-events-none absolute inset-0 overflow-hidden">
        <div className="absolute -left-32 top-48 h-96 w-96 rounded-full bg-[#d9e8ff] blur-3xl" />
        <div className="absolute -right-24 bottom-12 h-80 w-80 rounded-full bg-[#ffe6a8] blur-3xl" />
      </div>

      <nav className="relative z-10 mx-auto flex max-w-6xl items-center justify-between px-6 py-6">
        <Link to="/" className="flex items-center gap-3 font-semibold tracking-tight">
          <span className="grid size-9 place-items-center rounded-xl bg-[#171717] text-white">
            OC
          </span>
          OpenCut
        </Link>
        <Link
          to="/editor"
          className="rounded-full border border-black/10 bg-white px-5 py-2.5 text-sm font-medium shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
        >
          Open editor
        </Link>
      </nav>

      <section className="relative z-10 mx-auto grid min-h-[calc(100vh-96px)] max-w-6xl items-center gap-12 px-6 pb-16 pt-8 lg:grid-cols-[1fr_1.05fr]">
        <div className="max-w-xl">
          <p className="mb-5 text-sm font-semibold uppercase tracking-[0.22em] text-[#77776f]">
            Free video editing
          </p>
          <h1 className="text-5xl leading-[0.95] font-semibold tracking-[-0.055em] sm:text-6xl lg:text-7xl">
            Make great videos,
            <span className="block text-[#6868b8]">right in your browser.</span>
          </h1>
          <p className="mt-7 max-w-lg text-lg leading-8 text-[#62625b]">
            OpenCut is an open-source video editor designed to keep creating simple,
            fast, and accessible.
          </p>
          <div className="mt-9 flex flex-wrap items-center gap-3">
            <Link
              to="/editor"
              className="rounded-full bg-[#171717] px-6 py-3.5 text-sm font-semibold text-white shadow-lg shadow-black/10 transition hover:-translate-y-0.5 hover:bg-black"
            >
              Start creating
            </Link>
            <a
              href="https://github.com/opencut-app/opencut"
              target="_blank"
              rel="noreferrer"
              className="rounded-full px-5 py-3.5 text-sm font-semibold text-[#4f4f49] transition hover:bg-black/5"
            >
              View source
            </a>
          </div>
        </div>

        <div className="relative mx-auto w-full max-w-[620px]">
          <div className="absolute -inset-6 rounded-[2rem] bg-white/50 blur-xl" />
          <div className="relative overflow-hidden rounded-[1.35rem] border border-black/10 bg-[#202124] p-3 shadow-[0_30px_80px_rgba(0,0,0,0.18)]">
            <div className="flex items-center gap-1.5 px-2 pb-3">
              <span className="size-2.5 rounded-full bg-[#ff6b60]" />
              <span className="size-2.5 rounded-full bg-[#f6bd4f]" />
              <span className="size-2.5 rounded-full bg-[#61c454]" />
            </div>
            <div className="grid h-[360px] grid-cols-[74px_1fr] overflow-hidden rounded-xl bg-[#151619]">
              <aside className="border-r border-white/8 p-2">
                <div className="mb-2 h-6 rounded-md bg-white/10" />
                {[0, 1, 2, 3].map((item) => (
                  <div key={item} className="mb-2 h-12 rounded-md bg-white/[0.055]" />
                ))}
              </aside>
              <div className="grid grid-rows-[1fr_112px]">
                <div className="grid place-items-center bg-[#25272b]">
                  <div className="grid size-40 place-items-center rounded-2xl border border-white/10 bg-gradient-to-br from-[#8e8ef0] to-[#efb55d] shadow-2xl">
                    <div className="size-14 rotate-45 rounded-xl border-4 border-white/70" />
                  </div>
                </div>
                <div className="border-t border-white/8 bg-[#1b1c20] p-3">
                  <div className="mb-2 h-1 rounded-full bg-white/10">
                    <div className="h-full w-2/5 rounded-full bg-[#8e8ef0]" />
                  </div>
                  <div className="grid grid-cols-[repeat(8,minmax(0,1fr))] gap-1.5 pt-2">
                    {['#8e8ef0', '#efb55d', '#8e8ef0', '#78bea1', '#ef9e7b', '#78bea1', '#efb55d', '#8e8ef0'].map(
                      (color, index) => (
                        <div
                          key={`${color}-${index}`}
                          className="h-14 rounded-md"
                          style={{ backgroundColor: color, opacity: 0.78 }}
                        />
                      ),
                    )}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
    </main>
  )
}
