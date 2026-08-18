max_threads = Integer(ENV.fetch("PUMA_MAX_THREADS", "3"))
threads 1, max_threads

port ENV.fetch("PORT", "3000")
environment ENV.fetch("RACK_ENV", "development")

workers 0
