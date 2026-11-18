import os
import subprocess
import tempfile
from pathlib import Path

script = Path(__file__).resolve().with_name('sync-upstream.sh')

def git(cwd, *args):
    return subprocess.check_output(['git', '-C', str(cwd), *args], text=True, stderr=subprocess.DEVNULL).strip()

def commit(repo, filename, contents, message):
    (repo / filename).parent.mkdir(parents=True, exist_ok=True)
    (repo / filename).write_text(contents)
    git(repo, 'add', filename)
    git(repo, 'commit', '-m', message)
    return git(repo, 'rev-parse', 'HEAD')

def identity(repo):
    git(repo, 'config', 'user.name', 'Sync Test')
    git(repo, 'config', 'user.email', 'sync-test@example.invalid')

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    source, upstream, origin, fork = [root / x for x in ('source', 'upstream.git', 'origin.git', 'fork')]
    subprocess.run(['git', 'init', '-q', '-b', 'main', source], check=True)
    identity(source)
    commit(source, 'upstream.txt', 'original\n', 'initial')
    commit(source, '.github/workflows/check.yml', 'name: upstream original\n', 'initial upstream workflow')
    subprocess.run(['git', 'clone', '-q', '--bare', source, upstream], check=True)
    subprocess.run(['git', 'clone', '-q', '--bare', source, origin], check=True)
    subprocess.run(['git', 'clone', '-q', origin, fork], check=True)
    identity(fork)
    commit(fork, 'fork-only.txt', 'must survive\n', 'fork change')
    commit(fork, '.github/workflows/check.yml', 'name: fork workflow\n', 'fork workflow change')
    git(fork, 'push', 'origin', 'main')
    old_fork_head = git(fork, 'rev-parse', 'HEAD')
    commit(source, 'upstream.txt', 'new upstream content\n', 'upstream update')
    commit(source, '.github/workflows/check.yml', 'name: new upstream workflow\n', 'upstream workflow update')
    upstream_sha = commit(source, '.github/workflows/new.yml', 'name: newly added workflow\n', 'new upstream workflow')
    git(source, 'push', str(upstream), 'main')
    env = {**os.environ, 'UPSTREAM_URL': str(upstream), 'GITHUB_OUTPUT': str(root / 'outputs')}
    first = subprocess.run(['bash', str(script)], cwd=fork, env=env, capture_output=True, text=True)
    assert first.returncode == 0, first.stderr
    assert (fork / 'fork-only.txt').read_text() == 'must survive\n'
    assert (fork / 'upstream.txt').read_text() == 'new upstream content\n'
    assert (fork / '.github/workflows/check.yml').read_text() == 'name: fork workflow\n'
    assert not (fork / '.github/workflows/new.yml').exists()
    merged = git(fork, 'rev-parse', 'HEAD')
    assert git(fork, 'diff', '--name-only', old_fork_head, merged, '--', '.github/workflows') == ''
    assert (fork / 'docker/upstream-source.sha').read_text().strip() == upstream_sha
    # The push introduces only fork-owned source commits, so GITHUB_TOKEN does
    # not need permission to import upstream workflow-file history.
    assert subprocess.run(['git', '-C', str(fork), 'merge-base', '--is-ancestor', upstream_sha, merged]).returncode == 1
    assert git(origin, 'rev-parse', 'main') == merged
    assert f'upstream_sha={upstream_sha}' in (root / 'outputs').read_text()
    second = subprocess.run(['bash', str(script)], cwd=fork, env=env, capture_output=True, text=True)
    assert second.returncode == 0, second.stderr
    assert git(fork, 'rev-parse', 'HEAD') == merged
    print('PASS: source updates apply, fork workflows survive, upstream workflow history is excluded, repeated sync is idempotent')

    commit(source, 'new-source.txt', 'second source update\n', 'second upstream update')
    git(source, 'push', str(upstream), 'main')
    subsequent = subprocess.run(['bash', str(script)], cwd=fork, env=env, capture_output=True, text=True)
    assert subsequent.returncode == 0, subsequent.stderr
    assert (fork / 'new-source.txt').read_text() == 'second source update\n'
    print('PASS: subsequent updates use the recorded upstream source commit')

    commit(fork, 'upstream.txt', 'fork conflicting content\n', 'local conflicting edit')
    git(fork, 'push', 'origin', 'main')
    before_conflict = git(origin, 'rev-parse', 'main')
    commit(source, 'upstream.txt', 'upstream conflicting content\n', 'upstream conflicting edit')
    git(source, 'push', str(upstream), 'main')
    failed = subprocess.run(['bash', str(script)], cwd=fork, env=env, capture_output=True, text=True)
    assert failed.returncode != 0
    assert git(origin, 'rev-parse', 'main') == before_conflict
    assert git(fork, 'status', '--porcelain') == ''
    assert (fork / 'fork-only.txt').read_text() == 'must survive\n'
    print('PASS: conflict fails, aborts local merge, and leaves remote branch and fork changes intact')

    (fork / 'fork-only.txt').write_text('uncommitted user work\n')
    dirty = subprocess.run(['bash', str(script)], cwd=fork, env=env, capture_output=True, text=True)
    assert dirty.returncode != 0
    assert (fork / 'fork-only.txt').read_text() == 'uncommitted user work\n'
    assert git(origin, 'rev-parse', 'main') == before_conflict
    print('PASS: uncommitted user work is rejected and preserved')
