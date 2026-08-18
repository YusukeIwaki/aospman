FROM ruby:4.0.0-slim AS gems

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential libssl-dev pkg-config \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle config set path /usr/local/bundle \
  && bundle config set deployment true \
  && bundle install --jobs 4 --retry 3

FROM ruby:4.0.0-slim

ENV RACK_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle

WORKDIR /app
COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY . .

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
