#!/bin/bash

# 두 서브모듈에 자동으로 커밋 메시지를 생성하여 커밋하는 스크립트

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 커밋 메시지 생성 함수
generate_commit_message() {
    local repo_dir="$1"
    local repo_name="$2"
    
    cd "$repo_dir"
    
    # 변경사항이 없으면 빈 문자열 반환
    if [ -z "$(git status --porcelain)" ]; then
        echo ""
        return
    fi
    
    # 변경된 파일 목록 가져오기
    local modified_files=$(git status --short | awk '{print $2}' | tr '\n' ' ')
    local new_files=$(git status --short | grep '^??' | awk '{print $2}' | tr '\n' ' ')
    local changed_files=$(git status --short | grep '^ M' | awk '{print $2}' | tr '\n' ' ')
    
    # 주요 변경사항 분석
    local message_parts=()
    
    # 새 파일이 있는지 확인
    if [[ "$new_files" == *"talleres-config"* ]] || [[ "$new_files" == *"talleres-types"* ]] || [[ "$new_files" == *"vendor-talleres-types"* ]]; then
        message_parts+=("feat: add talleres configuration and types management")
    fi
    
    if [[ "$new_files" == *"vendor-talleres-types"* ]]; then
        message_parts+=("feat: implement many-to-many relationship between vendors and talleres types")
    fi
    
    # 수정된 파일 분석
    if [[ "$changed_files" == *"vendor.model"* ]] || [[ "$changed_files" == *"vendor.service"* ]] || [[ "$changed_files" == *"vendor.controller"* ]]; then
        if [[ "$message_parts" != *"many-to-many"* ]]; then
            message_parts+=("feat: add talleres types support to vendors")
        fi
    fi
    
    if [[ "$changed_files" == *"talleres-config"* ]]; then
        message_parts+=("feat: add talleres configuration endpoint")
    fi
    
    if [[ "$changed_files" == *"modules.seed"* ]] || [[ "$changed_files" == *"functions-seed"* ]]; then
        message_parts+=("chore: update seed files for talleres module")
    fi
    
    if [[ "$changed_files" == *"storeConfig.model"* ]]; then
        message_parts+=("feat: add talleresType field to store config")
    fi
    
    # 기본 메시지 (분석 실패 시)
    if [ ${#message_parts[@]} -eq 0 ]; then
        local file_count=$(git status --short | wc -l | tr -d ' ')
        if [ "$file_count" -gt 0 ]; then
            message_parts+=("chore: update $repo_name files")
        fi
    fi
    
    # 메시지 조합
    if [ ${#message_parts[@]} -gt 0 ]; then
        echo "${message_parts[0]}"
    else
        echo ""
    fi
}

echo "=========================================="
echo "자동 커밋 메시지 생성 및 커밋 시작..."
echo "=========================================="

# api-ventago 커밋 메시지 생성 및 커밋
echo ""
echo "--- api-ventago 분석 중 ---"
cd "$ROOT_DIR/api-ventago"
COMMIT_MSG_API=$(generate_commit_message "$ROOT_DIR/api-ventago" "api-ventago")

if [ -n "$COMMIT_MSG_API" ] && [ -n "$(git status --porcelain)" ]; then
    echo "생성된 커밋 메시지: $COMMIT_MSG_API"
    git add .
    git commit -m "$COMMIT_MSG_API"
    echo "✓ api-ventago 커밋 완료"
else
    if [ -z "$(git status --porcelain)" ]; then
        echo "⚠ api-ventago: 커밋할 변경사항이 없습니다"
    else
        echo "⚠ api-ventago: 커밋 메시지 생성 실패"
    fi
fi

# ventago-app 커밋 메시지 생성 및 커밋
echo ""
echo "--- ventago-app 분석 중 ---"
cd "$ROOT_DIR/ventago-app"
COMMIT_MSG_APP=$(generate_commit_message "$ROOT_DIR/ventago-app" "ventago-app")

if [ -n "$COMMIT_MSG_APP" ] && [ -n "$(git status --porcelain)" ]; then
    echo "생성된 커밋 메시지: $COMMIT_MSG_APP"
    git add .
    git commit -m "$COMMIT_MSG_APP"
    echo "✓ ventago-app 커밋 완료"
else
    if [ -z "$(git status --porcelain)" ]; then
        echo "⚠ ventago-app: 커밋할 변경사항이 없습니다"
    else
        echo "⚠ ventago-app: 커밋 메시지 생성 실패"
    fi
fi

echo ""
echo "=========================================="
echo "커밋 완료!"
echo "=========================================="
echo ""
echo "다음 명령어로 push할 수 있습니다:"
echo "  ./push-both.sh"
