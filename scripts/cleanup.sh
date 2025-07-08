#!/bin/bash

# 微前端404重定向PoC系统清理脚本
# 清理所有AWS资源

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 使用说明
usage() {
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --force    强制清理，忽略错误"
    echo "  --yes      跳过确认提示"
    echo "  --help     显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                # 交互式清理"
    echo "  $0 --yes          # 自动确认清理"
    echo "  $0 --force --yes  # 强制清理，跳过确认"
    exit 1
}

# 解析命令行参数
FORCE_MODE=false
AUTO_YES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --yes)
            AUTO_YES=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            log_error "未知参数: $1"
            usage
            ;;
    esac
done

# 确认清理操作
confirm_cleanup() {
    if [ "$AUTO_YES" = "true" ]; then
        return 0
    fi
    
    echo ""
    log_warning "此操作将删除以下AWS资源:"
    echo "  - CloudFront分发"
    echo "  - Lambda@Edge函数"
    echo "  - S3存储桶及其内容"
    echo "  - Origin Access Identity"
    echo "  - IAM角色和策略"
    echo ""
    read -p "确认继续清理？(y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "清理操作已取消"
        exit 0
    fi
}

# 安全执行命令
safe_execute() {
    local command="$1"
    local description="$2"
    
    if [ "$FORCE_MODE" = "true" ]; then
        eval "$command" 2>/dev/null || log_warning "$description 失败，但继续执行"
    else
        if eval "$command" 2>/dev/null; then
            log_success "$description 成功"
        else
            log_error "$description 失败"
            return 1
        fi
    fi
}

# 从部署信息文件读取资源信息
load_deployment_info() {
    if [ -f "deployment-info.json" ]; then
        log_info "从 deployment-info.json 读取部署信息..."
        
        DISTRIBUTION_ID=$(jq -r '.distributionId // empty' deployment-info.json 2>/dev/null)
        LAMBDA_FUNCTION=$(jq -r '.lambdaFunction // empty' deployment-info.json 2>/dev/null)
        S3_BUCKET=$(jq -r '.s3Bucket // empty' deployment-info.json 2>/dev/null)
        OAI_ID=$(jq -r '.oaiId // empty' deployment-info.json 2>/dev/null)
        AWS_REGION=$(jq -r '.region // empty' deployment-info.json 2>/dev/null)
        
        log_info "找到部署信息:"
        [ -n "$DISTRIBUTION_ID" ] && log_info "  CloudFront分发: $DISTRIBUTION_ID"
        [ -n "$LAMBDA_FUNCTION" ] && log_info "  Lambda函数: $LAMBDA_FUNCTION"
        [ -n "$S3_BUCKET" ] && log_info "  S3存储桶: $S3_BUCKET"
        [ -n "$OAI_ID" ] && log_info "  OAI ID: $OAI_ID"
        [ -n "$AWS_REGION" ] && log_info "  区域: $AWS_REGION"
    else
        log_warning "未找到 deployment-info.json，将尝试自动发现资源"
        auto_discover_resources
    fi
}

# 自动发现资源
auto_discover_resources() {
    log_info "自动发现AWS资源..."
    
    # 获取当前区域
    AWS_REGION=$(aws configure get region || echo "us-east-1")
    
    # 查找相关的CloudFormation栈
    local stacks=$(aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query 'StackSummaries[?contains(StackName, `micro-frontend-404-poc`)].StackName' \
        --output text --region $AWS_REGION 2>/dev/null || echo "")
    
    if [ -n "$stacks" ]; then
        log_info "找到CloudFormation栈: $stacks"
        STACK_NAME=$(echo $stacks | cut -d' ' -f1)
    fi
    
    # 查找Lambda函数
    local functions=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `micro-frontend-404-poc`)].FunctionName' \
        --output text --region us-east-1 2>/dev/null || echo "")
    
    if [ -n "$functions" ]; then
        LAMBDA_FUNCTION=$(echo $functions | cut -d' ' -f1)
        log_info "找到Lambda函数: $LAMBDA_FUNCTION"
    fi
    
    # 查找S3存储桶
    local buckets=$(aws s3api list-buckets \
        --query 'Buckets[?contains(Name, `micro-frontend-404-poc`)].Name' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$buckets" ]; then
        S3_BUCKET=$(echo $buckets | cut -d' ' -f1)
        log_info "找到S3存储桶: $S3_BUCKET"
    fi
}

# 禁用CloudFront分发
disable_cloudfront_distribution() {
    if [ -z "$DISTRIBUTION_ID" ]; then
        log_warning "未找到CloudFront分发ID，跳过"
        return 0
    fi
    
    log_info "禁用CloudFront分发: $DISTRIBUTION_ID"
    
    # 获取当前配置
    local config_file="temp-distribution-config.json"
    aws cloudfront get-distribution-config --id $DISTRIBUTION_ID > $config_file 2>/dev/null || {
        log_warning "无法获取CloudFront分发配置"
        return 0
    }
    
    local etag=$(jq -r '.ETag' $config_file)
    
    # 禁用分发
    jq '.DistributionConfig.Enabled = false' $config_file | jq '.DistributionConfig' > temp-config.json
    
    safe_execute "aws cloudfront update-distribution --id $DISTRIBUTION_ID --distribution-config file://temp-config.json --if-match $etag > /dev/null" "禁用CloudFront分发"
    
    rm -f $config_file temp-config.json
    
    log_info "等待CloudFront分发禁用..."
    sleep 30
}

# 删除CloudFront分发
delete_cloudfront_distribution() {
    if [ -z "$DISTRIBUTION_ID" ]; then
        log_warning "未找到CloudFront分发ID，跳过"
        return 0
    fi
    
    log_info "删除CloudFront分发: $DISTRIBUTION_ID"
    
    # 等待分发状态变为Deployed
    log_info "等待CloudFront分发状态更新..."
    local max_wait=300  # 5分钟
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        local status=$(aws cloudfront get-distribution --id $DISTRIBUTION_ID --query 'Distribution.Status' --output text 2>/dev/null || echo "NotFound")
        
        if [ "$status" = "Deployed" ]; then
            break
        elif [ "$status" = "NotFound" ]; then
            log_info "CloudFront分发已不存在"
            return 0
        fi
        
        sleep 30
        wait_time=$((wait_time + 30))
    done
    
    # 获取ETag并删除
    local etag=$(aws cloudfront get-distribution --id $DISTRIBUTION_ID --query 'ETag' --output text 2>/dev/null || echo "")
    
    if [ -n "$etag" ]; then
        safe_execute "aws cloudfront delete-distribution --id $DISTRIBUTION_ID --if-match $etag" "删除CloudFront分发"
    else
        log_warning "无法获取CloudFront分发ETag"
    fi
}

# 删除Lambda@Edge函数
delete_lambda_function() {
    if [ -z "$LAMBDA_FUNCTION" ]; then
        log_warning "未找到Lambda函数名，跳过"
        return 0
    fi
    
    log_info "删除Lambda@Edge函数: $LAMBDA_FUNCTION"
    
    # 删除所有版本
    local versions=$(aws lambda list-versions-by-function --function-name $LAMBDA_FUNCTION --query 'Versions[?Version!=`$LATEST`].Version' --output text --region us-east-1 2>/dev/null || echo "")
    
    for version in $versions; do
        safe_execute "aws lambda delete-function --function-name $LAMBDA_FUNCTION --qualifier $version --region us-east-1" "删除Lambda函数版本 $version"
    done
    
    # 删除函数
    safe_execute "aws lambda delete-function --function-name $LAMBDA_FUNCTION --region us-east-1" "删除Lambda函数"
    
    # 删除IAM角色
    local role_name="${LAMBDA_FUNCTION}-role"
    safe_execute "aws iam detach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" "分离IAM策略"
    safe_execute "aws iam delete-role --role-name $role_name" "删除IAM角色"
}

# 删除S3存储桶
delete_s3_bucket() {
    if [ -z "$S3_BUCKET" ]; then
        log_warning "未找到S3存储桶名，跳过"
        return 0
    fi
    
    log_info "删除S3存储桶: $S3_BUCKET"
    
    # 删除存储桶内容
    safe_execute "aws s3 rm s3://$S3_BUCKET --recursive --region ${AWS_REGION:-us-east-1}" "清空S3存储桶"
    
    # 删除存储桶
    safe_execute "aws s3 rb s3://$S3_BUCKET --region ${AWS_REGION:-us-east-1}" "删除S3存储桶"
}

# 删除Origin Access Identity
delete_oai() {
    if [ -z "$OAI_ID" ]; then
        log_warning "未找到OAI ID，跳过"
        return 0
    fi
    
    log_info "删除Origin Access Identity: $OAI_ID"
    
    local etag=$(aws cloudfront get-cloud-front-origin-access-identity --id $OAI_ID --query 'ETag' --output text 2>/dev/null || echo "")
    
    if [ -n "$etag" ]; then
        safe_execute "aws cloudfront delete-cloud-front-origin-access-identity --id $OAI_ID --if-match $etag" "删除Origin Access Identity"
    else
        log_warning "无法获取OAI ETag"
    fi
}

# 删除CloudFormation栈
delete_cloudformation_stack() {
    if [ -z "$STACK_NAME" ]; then
        return 0
    fi
    
    log_info "删除CloudFormation栈: $STACK_NAME"
    safe_execute "aws cloudformation delete-stack --stack-name $STACK_NAME --region ${AWS_REGION:-us-east-1}" "删除CloudFormation栈"
}

# 清理本地文件
cleanup_local_files() {
    log_info "清理本地临时文件..."
    
    rm -f deployment-info.json
    rm -f temp-*.json
    rm -f bucket-policy.json
    rm -f distribution-config.json
    
    log_success "本地文件清理完成"
}

# 主函数
main() {
    echo "🧹 微前端404重定向PoC系统清理"
    echo "=================================================="
    echo ""
    
    # 检查AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI未安装"
        exit 1
    fi
    
    # 检查AWS凭证
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS凭证未配置"
        exit 1
    fi
    
    # 加载部署信息
    load_deployment_info
    
    # 确认清理
    confirm_cleanup
    
    echo ""
    log_info "开始清理AWS资源..."
    
    # 按顺序清理资源
    disable_cloudfront_distribution
    delete_cloudfront_distribution
    delete_lambda_function
    delete_s3_bucket
    delete_oai
    delete_cloudformation_stack
    cleanup_local_files
    
    echo ""
    log_success "清理完成！"
    echo ""
    log_info "已清理的资源:"
    [ -n "$DISTRIBUTION_ID" ] && echo "  ✅ CloudFront分发: $DISTRIBUTION_ID"
    [ -n "$LAMBDA_FUNCTION" ] && echo "  ✅ Lambda函数: $LAMBDA_FUNCTION"
    [ -n "$S3_BUCKET" ] && echo "  ✅ S3存储桶: $S3_BUCKET"
    [ -n "$OAI_ID" ] && echo "  ✅ Origin Access Identity: $OAI_ID"
    [ -n "$STACK_NAME" ] && echo "  ✅ CloudFormation栈: $STACK_NAME"
    echo ""
    log_warning "注意: CloudFront分发删除可能需要额外时间完成"
}

# 执行主函数
main "$@"
