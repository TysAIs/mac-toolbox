#!/usr/bin/env bash
# twitter-env.sh — REQUIRED preflight for every `twitter` (twitter-cli) call.
# Sources ~/.mac-toolbox/cookies/twitter.env into the process environment.
# Cookie contract: TWITTER_AUTH_TOKEN + TWITTER_CT0 only. Never prints values.
set -a
[ -f "$HOME/.mac-toolbox/cookies/twitter.env" ] && . "$HOME/.mac-toolbox/cookies/twitter.env"
[ -f "$HOME/.mac-toolbox/cookies/proxy.env" ] && . "$HOME/.mac-toolbox/cookies/proxy.env"
set +a
