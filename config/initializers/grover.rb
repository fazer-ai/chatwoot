# Grover config for the conversation transcript PDF download.
#
# Each Grover.new(html).to_pdf call spawns its own Node.js + Chromium subprocess.
# That gives us hard isolation between concurrent renders (no shared memory or
# state), so two users downloading the same transcript at the same time can
# never contaminate each other's PDF.
#
# The concurrency cap that protects against OOM (each Chromium is ~150MB) lives
# in Conversations::TranscriptPdfService via a Concurrent::Semaphore — not here.

# Skip in test to avoid spawning Chromium during the suite.
return if Rails.env.test?

# Where the Chromium binary lives inside the Alpine image (installed by the
# Dockerfile via `apk add chromium`). Falling back to whatever puppeteer would
# find by itself when the env var is not set (dev/mac).
puppeteer_executable_path = ENV.fetch('PUPPETEER_EXECUTABLE_PATH', nil)

Grover.configure do |config|
  config.options = {
    format: 'A4',
    margin: {
      top: '1.2cm',
      bottom: '1.2cm',
      left: '1.5cm',
      right: '1.5cm'
    },
    print_background: true,
    # Prevent HTML render from hanging forever if a remote asset (attachment link)
    # is slow — the transcript PDF is not worth a stuck Puma thread.
    timeout: 20_000,
    launch_args: [
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--single-process'
    ],
    executable_path: puppeteer_executable_path
  }.compact
end
