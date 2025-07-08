#!/bin/bash

# 微前端404重定向PoC系统测试脚本
# 基于实际成功测试经验优化

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
    echo "使用方法: $0 <cloudfront-domain> [verbose] [iterations] [timeout]"
    echo ""
    echo "参数:"
    echo "  cloudfront-domain  CloudFront分发域名 (必需)"
    echo "  verbose           详细模式 (可选, true/false, 默认: false)"
    echo "  iterations        性能测试迭代次数 (可选, 默认: 3)"
    echo "  timeout           单个请求超时时间 (可选, 默认: 30秒)"
    echo ""
    echo "示例:"
    echo "  $0 d1234567890.cloudfront.net"
    echo "  $0 d1234567890.cloudfront.net true"
    echo "  $0 d1234567890.cloudfront.net true 5 60"
    exit 1
}

# 检查参数
if [ $# -lt 1 ]; then
    usage
fi

# 设置变量
CLOUDFRONT_DOMAIN=$1
VERBOSE=${2:-false}
ITERATIONS=${3:-3}
TIMEOUT=${4:-30}

# 验证域名格式
if [[ ! $CLOUDFRONT_DOMAIN =~ ^[a-z0-9]+\.cloudfront\.net$ ]]; then
    log_error "无效的CloudFront域名格式: $CLOUDFRONT_DOMAIN"
    log_info "正确格式: d1234567890.cloudfront.net"
    exit 1
fi

# 检查curl是否可用
if ! command -v curl &> /dev/null; then
    log_error "curl未安装，请先安装curl"
    exit 1
fi

# 测试HTTP请求
test_http_request() {
    local url=$1
    local expected_status=$2
    local description=$3
    local follow_redirects=${4:-false}
    
    if [ "$VERBOSE" = "true" ]; then
        log_info "测试: $description"
        log_info "URL: $url"
        log_info "期望状态: $expected_status"
    fi
    
    local curl_options="-s -w HTTPSTATUS:%{http_code};TIME:%{time_total};REDIRECT:%{redirect_url} --max-time $TIMEOUT"
    
    if [ "$follow_redirects" = "true" ]; then
        curl_options="$curl_options -L"
    fi
    
    local response=$(curl $curl_options "$url" 2>/dev/null || echo "HTTPSTATUS:000;TIME:0;REDIRECT:")
    local http_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local time_total=$(echo "$response" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
    local redirect_url=$(echo "$response" | grep -o "REDIRECT:[^;]*" | cut -d: -f2-)
    
    if [ "$http_code" = "$expected_status" ]; then
        if [ "$VERBOSE" = "true" ]; then
            log_success "$description - HTTP $http_code (${time_total}s)"
            if [ -n "$redirect_url" ] && [ "$redirect_url" != "" ]; then
                log_info "重定向到: $redirect_url"
            fi
        fi
        return 0
    else
        if [ "$VERBOSE" = "true" ]; then
            log_error "$description - HTTP $http_code (期望 $expected_status)"
        fi
        return 1
    fi
}

# 性能测试
performance_test() {
    local url=$1
    local description=$2
    
    log_info "性能测试: $description"
    
    local total_time=0
    local success_count=0
    local min_time=999
    local max_time=0
    
    for i in $(seq 1 $ITERATIONS); do
        local time_result=$(curl -s -w "%{time_total}" -o /dev/null --max-time $TIMEOUT "$url" 2>/dev/null || echo "0")
        
        if [ "$time_result" != "0" ] && [ "$(echo "$time_result > 0" | bc -l 2>/dev/null || echo "0")" = "1" ]; then
            total_time=$(echo "$total_time + $time_result" | bc -l 2>/dev/null || echo "$total_time")
            success_count=$((success_count + 1))
            
            # 更新最小和最大时间
            if [ "$(echo "$time_result < $min_time" | bc -l 2>/dev/null || echo "0")" = "1" ]; then
                min_time=$time_result
            fi
            if [ "$(echo "$time_result > $max_time" | bc -l 2>/dev/null || echo "0")" = "1" ]; then
                max_time=$time_result
            fi
        fi
        
        sleep 1
    done
    
    if [ $success_count -gt 0 ]; then
        local avg_time=$(echo "scale=3; $total_time / $success_count" | bc -l 2>/dev/null || echo "N/A")
        log_success "平均响应时间: ${avg_time}s (最小: ${min_time}s, 最大: ${max_time}s, 成功: $success_count/$ITERATIONS)"
    else
        log_error "所有请求失败"
    fi
}

# 主测试函数
main() {
    echo "🧪 微前端404重定向PoC系统测试"
    echo "=================================================="
    echo "CloudFront域名: $CLOUDFRONT_DOMAIN"
    echo "测试时间: $(date)"
    echo "详细模式: $VERBOSE"
    echo "性能测试迭代: $ITERATIONS"
    echo ""
    
    # 测试计数器
    local total_tests=0
    local passed_tests=0
    
    # 1. 基础连通性测试
    echo "🔍 1. 基础连通性测试"
    echo "-----------------------------------"
    
    # 测试主页
    total_tests=$((total_tests + 1))
    echo -n "主页访问: "
    if test_http_request "https://$CLOUDFRONT_DOMAIN/" "200" "主页访问"; then
        echo "✅ 成功"
        passed_tests=$((passed_tests + 1))
    else
        echo "❌ 失败"
    fi
    
    # 测试直接文件访问
    for app in "website1" "website2" "app1"; do
        total_tests=$((total_tests + 1))
        echo -n "$app/index.html: "
        if test_http_request "https://$CLOUDFRONT_DOMAIN/$app/index.html" "200" "$app直接文件访问"; then
            echo "✅ 成功"
            passed_tests=$((passed_tests + 1))
        else
            echo "❌ 失败"
        fi
    done
    
    echo ""
    
    # 2. 子目录重定向测试
    echo "🔍 2. 子目录重定向测试"
    echo "-----------------------------------"
    
    for app in "website1" "website2" "app1"; do
        total_tests=$((total_tests + 1))
        echo -n "$app 子目录重定向: "
        if test_http_request "https://$CLOUDFRONT_DOMAIN/$app/" "302" "$app子目录重定向"; then
            echo "✅ 成功"
            passed_tests=$((passed_tests + 1))
        else
            echo "❌ 失败"
        fi
    done
    
    echo ""
    
    # 3. 404重定向测试
    echo "🔍 3. 404重定向测试"
    echo "-----------------------------------"
    
    for app in "website1" "website2" "app1"; do
        total_tests=$((total_tests + 1))
        echo -n "$app 404重定向: "
        local test_url="https://$CLOUDFRONT_DOMAIN/$app/missing-page-$(date +%s)"
        if test_http_request "$test_url" "302" "$app 404重定向"; then
            echo "✅ 成功"
            passed_tests=$((passed_tests + 1))
        else
            echo "❌ 失败"
        fi
    done
    
    echo ""
    
    # 4. 完整流程测试
    echo "🔍 4. 完整流程测试"
    echo "-----------------------------------"
    
    for app in "website1" "website2" "app1"; do
        total_tests=$((total_tests + 1))
        echo -n "$app 完整流程: "
        if test_http_request "https://$CLOUDFRONT_DOMAIN/$app/" "200" "$app完整流程" "true"; then
            echo "✅ 成功"
            passed_tests=$((passed_tests + 1))
        else
            echo "❌ 失败"
        fi
    done
    
    echo ""
    
    # 5. 性能测试
    if [ $ITERATIONS -gt 0 ]; then
        echo "🔍 5. 性能测试"
        echo "-----------------------------------"
        
        performance_test "https://$CLOUDFRONT_DOMAIN/" "主页访问"
        performance_test "https://$CLOUDFRONT_DOMAIN/website1/" "Website1重定向"
        performance_test "https://$CLOUDFRONT_DOMAIN/website2/" "Website2重定向"
        performance_test "https://$CLOUDFRONT_DOMAIN/app1/" "App1重定向"
        
        echo ""
    fi
    
    # 测试结果总结
    local success_rate=$(echo "scale=1; $passed_tests * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
    
    echo "🎯 测试结果总结"
    echo "=================================================="
    echo "📊 测试统计:"
    echo "  通过测试: $passed_tests/$total_tests"
    echo "  成功率: $success_rate%"
    echo "  测试时间: $(date)"
    echo ""
    
    if [ "$success_rate" = "100.0" ] || [ "$passed_tests" -eq "$total_tests" ]; then
        log_success "所有测试通过！系统功能正常"
        echo ""
        echo "🔗 可用链接:"
        echo "  主页: https://$CLOUDFRONT_DOMAIN/"
        echo "  Website1: https://$CLOUDFRONT_DOMAIN/website1/"
        echo "  Website2: https://$CLOUDFRONT_DOMAIN/website2/"
        echo "  App1: https://$CLOUDFRONT_DOMAIN/app1/"
        echo ""
        echo "🧪 404重定向测试:"
        echo "  https://$CLOUDFRONT_DOMAIN/website1/any-missing-page"
        echo "  https://$CLOUDFRONT_DOMAIN/website2/non-existent-route"
        echo "  https://$CLOUDFRONT_DOMAIN/app1/404-test-page"
        
        exit 0
    elif [ "$passed_tests" -gt 0 ]; then
        log_warning "部分测试通过，系统可能仍在部署中"
        echo ""
        echo "📝 建议:"
        echo "- 等待5-10分钟后重新测试"
        echo "- CloudFront全球部署需要时间"
        echo "- 检查AWS控制台中的资源状态"
        
        exit 1
    else
        log_error "所有测试失败，系统可能有问题"
        echo ""
        echo "📝 故障排除:"
        echo "- 检查CloudFront分发状态"
        echo "- 验证Lambda@Edge函数部署"
        echo "- 查看CloudWatch日志"
        echo "- 确认S3存储桶权限配置"
        
        exit 2
    fi
}

# 执行主函数
main "$@"
