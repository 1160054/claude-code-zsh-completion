#!/bin/zsh
# Records demo.ja.gif: demo/demo.tape with the Japanese completion (_claude.ja)
# and Japanese fixture text (session prompts and names, background job names).
#
#   demo/make-ja.sh
#
# demo/ itself is left alone: it is copied to a temporary directory and the
# copy's fixtures are rewritten before recording.
set -e
R=${0:A:h:h}; T=$(mktemp -d)
cp -R $R/demo $T/demo
mkdir -p $T/completions && cp $R/completions/_claude.ja $T/completions/_claude
F=$T/demo/fixtures
rm -rf $F/home/.claude/projects   # rebuilt from sessions/ by the recording

# Sessions: the first prompt (the label) and, for the named one, its custom title
s() { print -r -- "{\"type\":\"summary\",\"summary\":\"demo session\"}
{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"$2\"}}$3" > $F/sessions/$1.jsonl }
s 3f6b1c20-8d4a-4e91-b7c2-1a5e9d0f3b84 'ヘルスチェックを追加'
s 7c2a94e1-5b60-4d3f-9a18-e4c7b2650df3 'nightly ビルドが落ちている原因は？'
s a3f8e2b1-9c4d-4e7a-b5f3-2d8c9a1e4f6b '認証を新しいルーターに移す'
s f7a2e4d9-3b8c-4f1e-a6d2-9c5b7e3a8f1d 'リトライ処理のテストを書いて'
s d41e7b02-5c9a-4f3e-b8d1-2a6f0c9e7b14 '今週の issue を仕分けてラベルを付けて' '
{"type":"custom-title","customTitle":"issue の仕分け","sessionId":"d41e7b02-5c9a-4f3e-b8d1-2a6f0c9e7b14"}'

# Background session names
j() { python3 - $F/home/.claude/jobs/$1/state.json "$2" <<'EOF'
import json,sys
p,n=sys.argv[1],sys.argv[2]; d=json.load(open(p)); d['name']=n
json.dump(d,open(p,'w'),ensure_ascii=False,indent=2)
EOF
}
j 1d7e9f20 'issue の仕分け'
j 5a7f0e21 '2.5 のリリースノートを書く'
j 9b1c2d3e '認証を新しいルーターに移行'
j c0ffee42 'nightly ビルドの調査'

# Tape: output path, a UTF-8 locale, and the --name and prompt typed in Japanese
sed -e "s#^Output .*#Output \"$R/demo.ja.gif\"#" \
    -e 's#^Type "unset CLAUDE_CONFIG_DIR"#Type "unset CLAUDE_CONFIG_DIR; export LC_ALL=ja_JP.UTF-8"#' \
    $R/demo/demo.tape > $T/demo/ja.tape
python3 - $T/demo/ja.tape <<'EOF'
import sys
p=sys.argv[1]; s=open(p).read()
old='''Type ` --name "triage open issues" "triage this week's issues"`'''
assert old in s, 'the --name line in demo.tape changed'
s=s.replace(old,'''Type ` --name "issue の仕分け" "今週の issue を仕分けて"`''')
open(p,'w').write(s)
EOF
grep -q 'LC_ALL=ja_JP' $T/demo/ja.tape

cd $T/demo && vhs ja.tape && gifsicle -O3 --lossy=30 -o $R/demo.ja.gif $R/demo.ja.gif
echo $R/demo.ja.gif
