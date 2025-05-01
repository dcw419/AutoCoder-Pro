#!/bin/bash

set -e
set -x

GITHUB_TOKEN="$1"
REPOSITORY="$2"
ISSUE_NUMBER="$3"
DEEPSEEK_API_KEY="$4"

# 获取 Issue 详情
fetch_issue_details() {
    curl -s -H "Authorization: token $GITHUB_TOKEN" \
         "https://api.github.com/repos/$REPOSITORY/issues/$ISSUE_NUMBER"
}

# 向 DeepSeek 发送 prompt 请求
send_prompt_to_deepseek() {
    curl -s -X POST "https://api.deepseek.com/v1/chat/completions" \
        -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"deepseek-coder\", \"messages\": $MESSAGES_JSON, \"max_tokens\": 500}"
}

# 保存代码到本地文件
save_to_file() {
    local filename="autocoder-bot/$1"
    local code_snippet="$2"

    mkdir -p "$(dirname "$filename")"
    echo -e "$code_snippet" > "$filename"
    echo "Saved code to $filename"
}

# ===== 主流程 =====

RESPONSE=$(fetch_issue_details)

# 标签检查：只有含有 autocoder-bot 标签才运行
HAS_LABEL=$(echo "$RESPONSE" | jq -r '.labels[].name' | grep -q 'autocoder-bot' && echo yes || echo no)
if [[ "$HAS_LABEL" != "yes" ]]; then
    echo "Label 'autocoder-bot' not found. Exiting."
    exit 0
fi

ISSUE_BODY=$(echo "$RESPONSE" | jq -r .body)
if [[ -z "$ISSUE_BODY" || "$ISSUE_BODY" == "null" ]]; then
    echo 'Issue body is empty.'
    exit 1
fi

INSTRUCTIONS="Please generate a JSON object where keys are file paths and values are code snippets for a production-ready app. Strict JSON only, no markdown."

FULL_PROMPT="$INSTRUCTIONS\n\n$ISSUE_BODY"

# ✅ 正确构造 JSON 数组
MESSAGES_JSON=$(jq -n --arg body "$FULL_PROMPT" '[{"role": "user", "content": $body}]')

RESPONSE=$(send_prompt_to_deepseek)

if [[ -z "$RESPONSE" ]]; then
    echo "No response from DeepSeek API."
    exit 1
fi

# 提取生成的 JSON 内容
FILES_JSON=$(echo "$RESPONSE" | jq -e '.choices[0].message.content | fromjson' 2>/dev/null)

if [[ -z "$FILES_JSON" ]]; then
    echo "Invalid JSON in DeepSeek response."
    exit 1
fi

# 保存每一个文件
for key in $(echo "$FILES_JSON" | jq -r 'keys[]'); do
    FILENAME=$key
    CODE_SNIPPET=$(echo "$FILES_JSON" | jq -r --arg key "$key" '.[$key]')
    CODE_SNIPPET=$(echo "$CODE_SNIPPET" | sed 's/\r$//')
    save_to_file "$FILENAME" "$CODE_SNIPPET"
done

echo "All code generated and saved."
