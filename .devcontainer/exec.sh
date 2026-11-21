#!/usr/bin/env bash
# Run a command in the running devcontainer. See AGENTS.md for the modes.
set -euo pipefail

LABEL=devcontainer.local_folder
FOLDER="$(cd "$(dirname "$0")/.." && pwd)"
SESSION=agent

# `docker exec` has no --ulimit flag, so raise the soft limit in the shell.
FD_PRERUN='ulimit -n 65536 >/dev/null 2>&1 || true; exec "$@"'

compose() {
    docker compose -f "$FOLDER/docker-compose.yml" --project-directory "$FOLDER" --profile dev "$@"
}

current=$(docker ps --filter "label=$LABEL=$FOLDER" --format '{{.Names}}' | head -n1)
if [ -z "$current" ]; then
    # Fall back to the dedicated `dev` Compose service. This is the supported
    # path for a plain host terminal (no VS Code required).
    current=$(compose ps -q dev 2>/dev/null | head -n1 || true)
    if [ -z "$current" ]; then
        echo "Starting the dev container (docker compose --profile dev up -d --build dev)..." >&2
        compose up -d --build dev >&2
        current=$(compose ps -q dev | head -n1)
    fi
fi

if [ -z "$current" ]; then
    stopped=$(docker ps -a --filter "label=$LABEL=$FOLDER" --format '{{.Names}}\t{{.Status}}' | head -n1)
    if [ -n "$stopped" ]; then
        echo "The devcontainer for $FOLDER is stopped: $stopped" >&2
        echo "Start it with:  docker start ${stopped%%$'\t'*}" >&2
    else
        echo "No devcontainer for $FOLDER." >&2
        echo "Open the folder in VS Code and choose Reopen in Container, or run:" >&2
        echo "  docker compose --profile dev up -d --build dev" >&2
    fi
    exit 1
fi

# Raw `docker exec` ignores remoteEnv. Fix the socket permissions and set the env.
docker exec "$current" chmod a+rwx /run/host-services 2>/dev/null || true
docker exec "$current" chmod a+rw /run/host-services/ssh-auth.sock 2>/dev/null || true
EXEC_ENV=(-e SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
          -e GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new')

# First run of the Compose `dev` service (or a fresh volume): warm the Cabal
# build cache once. post-create.sh writes the marker.
if ! docker exec "$current" test -f /workspace/dist-newstyle/.dev-ready 2>/dev/null; then
    echo "Preparing the dev container (Cabal dependencies + build)..." >&2
    docker exec -w /workspace "${EXEC_ENV[@]}" "$current" \
        bash .devcontainer/post-create.sh >&2
fi

# Mirror the caller's directory when it is inside the repo. Otherwise use /workspace.
case "$PWD" in
    "$FOLDER")   WORKDIR=/workspace ;;
    "$FOLDER"/*) WORKDIR="/workspace/${PWD#"$FOLDER"/}" ;;
    *)           WORKDIR=/workspace ;;
esac

mode=direct
while :; do
    case "${1:-}" in
        --watch)
            mode=watch
            shift
            ;;
        --interactive)
            mode=interactive
            shift
            ;;
        --dir)
            WORKDIR="${2:?--dir needs a path}"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done
case "$WORKDIR" in /*) ;; *) WORKDIR="/workspace/$WORKDIR" ;; esac

case "$mode" in
    interactive)
        if [ "$#" -eq 0 ]; then set -- bash; fi
        exec docker exec -it -w "$WORKDIR" "${EXEC_ENV[@]}" "$current" \
            bash -c "$FD_PRERUN" _ "$@"
        ;;

    watch)
        if [ "$#" -eq 0 ]; then
            echo "Usage: exec.sh --watch <command...>" >&2
            exit 64
        fi

        # Reuse one tmux session. Start it if it does not exist.
        if ! docker exec "$current" tmux has-session -t "$SESSION" >/dev/null 2>&1; then
            if ! docker exec "$current" tmux new-session -d -s "$SESSION" >/dev/null 2>&1; then
                echo "tmux is missing in the container. Rebuild the container." >&2
                exit 127
            fi
        fi

        stamp="$$$(date +%s)"
        log="/tmp/agent-console-${stamp}.log"
        mark="/tmp/agent-console-${stamp}.exit"
        runner="/tmp/agent-runner-${stamp}.sh"

        # Send a runner script through stdin to avoid quoting problems.
        esc=$(printf '%q ' "$@")
        inner="ulimit -n 65536 >/dev/null 2>&1 || true; set -o pipefail; { cd $(printf '%q' "$WORKDIR") && ${esc}; } 2>&1 | tee ${log}; echo \${PIPESTATUS[0]} > ${mark}"
        printf '#!/usr/bin/env bash\nbash -c %q\n' "$inner" \
            | docker exec -i "$current" bash -c "cat > ${runner} && chmod +x ${runner}"

        docker exec "$current" tmux new-window -t "$SESSION" -n "run-${stamp}" \
            "bash ${runner}" >/dev/null

        timeout="${EXEC_WATCH_TIMEOUT:-1800}"
        iters=0
        max_iters=$(( timeout * 10 / 3 ))
        while ! docker exec "$current" test -s "$mark" 2>/dev/null; do
            sleep 0.3
            iters=$((iters + 1))
            if [ "$iters" -ge "$max_iters" ]; then
                echo "--watch: timed out after ${timeout}s." >&2
                echo "The window 'run-${stamp}' in session '${SESSION}' is still alive." >&2
                exit 124
            fi
        done

        echo "=== agent-console (tmux session '${SESSION}', window 'run-${stamp}') ===" >&2
        docker exec "$current" cat "$log"
        rc=$(docker exec "$current" cat "$mark")
        docker exec "$current" rm -f "$log" "$mark" "$runner" 2>/dev/null || true
        exit "$rc"
        ;;
esac

if [ "$#" -eq 0 ]; then
    echo "Usage: exec.sh [--dir <path>] <command...>" >&2
    echo "       exec.sh [--dir <path>] --watch <command...>" >&2
    echo "       exec.sh [--dir <path>] --interactive" >&2
    exit 64
fi

exec docker exec -w "$WORKDIR" "${EXEC_ENV[@]}" "$current" bash -c "$FD_PRERUN" _ "$@"
