#!/bin/bash

# 微前端404重定向PoC系统部署脚本
# 基于实际成功部署经验优化

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

# 检查前置条件
check_prerequisites() {
    log_info "检查前置条件..."
    
    # 检查AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI未安装，请先安装AWS CLI"
        exit 1
    fi
    
    # 检查Node.js
    if ! command -v node &> /dev/null; then
        log_error "Node.js未安装，请先安装Node.js 18.x"
        exit 1
    fi
    
    # 检查jq
    if ! command -v jq &> /dev/null; then
        log_error "jq未安装，请先安装jq"
        exit 1
    fi
    
    # 检查AWS凭证
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS凭证未配置，请运行 'aws configure'"
        exit 1
    fi
    
    log_success "前置条件检查通过"
}

# 设置变量
setup_variables() {
    log_info "设置部署变量..."
    
    # 获取AWS账户ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # 获取当前区域
    AWS_REGION=$(aws configure get region || echo "us-east-1")
    
    # 如果是欧洲区域，Lambda@Edge必须在us-east-1
    LAMBDA_REGION="us-east-1"
    
    # 生成唯一的资源名称
    TIMESTAMP=$(date +%s)
    PROJECT_NAME="micro-frontend-404-poc"
    STACK_NAME="${PROJECT_NAME}-${AWS_REGION}"
    BUCKET_NAME="${PROJECT_NAME}-${AWS_ACCOUNT_ID}-${AWS_REGION}"
    FUNCTION_NAME="${PROJECT_NAME}-404-redirect"
    
    log_info "部署配置:"
    log_info "  AWS账户ID: $AWS_ACCOUNT_ID"
    log_info "  主区域: $AWS_REGION"
    log_info "  Lambda区域: $LAMBDA_REGION"
    log_info "  S3存储桶: $BUCKET_NAME"
    log_info "  Lambda函数: $FUNCTION_NAME"
}

# 创建S3存储桶
create_s3_bucket() {
    log_info "创建S3存储桶..."
    
    # 检查存储桶是否已存在
    if aws s3 ls "s3://$BUCKET_NAME" 2>/dev/null; then
        log_warning "S3存储桶已存在: $BUCKET_NAME"
    else
        # 创建存储桶
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb "s3://$BUCKET_NAME" --region $AWS_REGION
        else
            aws s3 mb "s3://$BUCKET_NAME" --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
        fi
        log_success "S3存储桶创建完成: $BUCKET_NAME"
    fi
    
    # 上传静态文件
    log_info "上传静态文件..."
    aws s3 sync src/static/ "s3://$BUCKET_NAME/" --region $AWS_REGION
    log_success "静态文件上传完成"
}

# 创建Origin Access Identity
create_oai() {
    log_info "创建CloudFront Origin Access Identity..."
    
    OAI_RESULT=$(aws cloudfront create-cloud-front-origin-access-identity \
        --cloud-front-origin-access-identity-config \
        CallerReference="$PROJECT_NAME-$TIMESTAMP",Comment="OAI for $PROJECT_NAME" \
        --query 'CloudFrontOriginAccessIdentity.Id' \
        --output text)
    
    OAI_ID=$OAI_RESULT
    log_success "Origin Access Identity创建完成: $OAI_ID"
    
    # 更新S3存储桶策略
    log_info "更新S3存储桶策略..."
    
    cat > bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity $OAI_ID"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file://bucket-policy.json --region $AWS_REGION
    rm -f bucket-policy.json
    log_success "S3存储桶策略更新完成"
}

# 部署Lambda@Edge函数
deploy_lambda_edge() {
    log_info "部署Lambda@Edge函数..."
    
    # 进入Lambda目录
    cd src/lambda
    
    # 创建部署包
    zip -r function.zip index.js package.json
    
    # 检查函数是否已存在
    if aws lambda get-function --function-name $FUNCTION_NAME --region $LAMBDA_REGION 2>/dev/null; then
        log_warning "Lambda函数已存在，更新代码..."
        aws lambda update-function-code \
            --function-name $FUNCTION_NAME \
            --zip-file fileb://function.zip \
            --region $LAMBDA_REGION > /dev/null
    else
        # 创建IAM角色
        log_info "创建Lambda执行角色..."
        
        cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": [
                    "lambda.amazonaws.com",
                    "edgelambda.amazonaws.com"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
        
        ROLE_ARN=$(aws iam create-role \
            --role-name "${FUNCTION_NAME}-role" \
            --assume-role-policy-document file://trust-policy.json \
            --query 'Role.Arn' \
            --output text)
        
        # 附加基本执行策略
        aws iam attach-role-policy \
            --role-name "${FUNCTION_NAME}-role" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        rm -f trust-policy.json
        
        # 等待角色生效
        log_info "等待IAM角色生效..."
        sleep 10
        
        # 创建Lambda函数
        aws lambda create-function \
            --function-name $FUNCTION_NAME \
            --runtime nodejs18.x \
            --role $ROLE_ARN \
            --handler index.handler \
            --zip-file fileb://function.zip \
            --timeout 5 \
            --memory-size 128 \
            --region $LAMBDA_REGION > /dev/null
        
        log_success "Lambda函数创建完成"
    fi
    
    # 发布版本
    log_info "发布Lambda函数版本..."
    LAMBDA_VERSION=$(aws lambda publish-version \
        --function-name $FUNCTION_NAME \
        --description "Production version for micro-frontend 404 redirect" \
        --region $LAMBDA_REGION \
        --query 'Version' \
        --output text)
    
    # 获取版本ARN
    LAMBDA_ARN=$(aws lambda get-function \
        --function-name $FUNCTION_NAME \
        --qualifier $LAMBDA_VERSION \
        --region $LAMBDA_REGION \
        --query 'Configuration.FunctionArn' \
        --output text)
    
    log_success "Lambda函数版本发布完成: $LAMBDA_VERSION"
    log_info "Lambda ARN: $LAMBDA_ARN"
    
    # 清理临时文件
    rm -f function.zip
    cd ../..
}

# 创建CloudFront分发
create_cloudfront_distribution() {
    log_info "创建CloudFront分发..."
    
    # 创建分发配置
    cat > distribution-config.json << EOF
{
    "CallerReference": "$PROJECT_NAME-$TIMESTAMP",
    "Comment": "Micro-frontend 404 redirect distribution",
    "Enabled": true,
    "DefaultRootObject": "index.html",
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3Origin",
                "DomainName": "$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com",
                "S3OriginConfig": {
                    "OriginAccessIdentity": "origin-access-identity/cloudfront/$OAI_ID"
                }
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000,
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            }
        },
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "LambdaFunctionAssociations": {
            "Quantity": 1,
            "Items": [
                {
                    "LambdaFunctionARN": "$LAMBDA_ARN",
                    "EventType": "origin-request"
                }
            ]
        }
    },
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": true
    }
}
EOF
    
    # 创建分发
    DISTRIBUTION_RESULT=$(aws cloudfront create-distribution \
        --distribution-config file://distribution-config.json)
    
    DISTRIBUTION_ID=$(echo $DISTRIBUTION_RESULT | jq -r '.Distribution.Id')
    CLOUDFRONT_DOMAIN=$(echo $DISTRIBUTION_RESULT | jq -r '.Distribution.DomainName')
    
    rm -f distribution-config.json
    
    log_success "CloudFront分发创建完成"
    log_info "  分发ID: $DISTRIBUTION_ID"
    log_info "  域名: $CLOUDFRONT_DOMAIN"
}

# 等待部署完成
wait_for_deployment() {
    log_info "等待CloudFront分发部署完成..."
    log_warning "这可能需要10-15分钟，请耐心等待..."
    
    # 简单等待，避免复杂的状态检查
    sleep 300  # 等待5分钟
    
    log_success "初始部署等待完成"
    log_warning "CloudFront可能需要额外5-10分钟完全生效"
}

# 保存部署信息
save_deployment_info() {
    log_info "保存部署信息..."
    
    cat > deployment-info.json << EOF
{
    "deploymentTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "projectName": "$PROJECT_NAME",
    "awsAccountId": "$AWS_ACCOUNT_ID",
    "region": "$AWS_REGION",
    "lambdaRegion": "$LAMBDA_REGION",
    "s3Bucket": "$BUCKET_NAME",
    "lambdaFunction": "$FUNCTION_NAME",
    "lambdaVersion": "$LAMBDA_VERSION",
    "lambdaArn": "$LAMBDA_ARN",
    "distributionId": "$DISTRIBUTION_ID",
    "cloudFrontDomain": "$CLOUDFRONT_DOMAIN",
    "oaiId": "$OAI_ID",
    "urls": {
        "home": "https://$CLOUDFRONT_DOMAIN/",
        "website1": "https://$CLOUDFRONT_DOMAIN/website1/",
        "website2": "https://$CLOUDFRONT_DOMAIN/website2/",
        "app1": "https://$CLOUDFRONT_DOMAIN/app1/"
    },
    "testUrls": {
        "website1_404": "https://$CLOUDFRONT_DOMAIN/website1/missing-page",
        "website2_404": "https://$CLOUDFRONT_DOMAIN/website2/non-existent",
        "app1_404": "https://$CLOUDFRONT_DOMAIN/app1/404-test"
    }
}
EOF
    
    log_success "部署信息已保存到 deployment-info.json"
}

# 显示部署结果
show_deployment_result() {
    echo ""
    echo "🎉 部署完成！"
    echo "=================================================="
    echo ""
    echo "📋 部署信息:"
    echo "  区域: $AWS_REGION"
    echo "  CloudFront域名: $CLOUDFRONT_DOMAIN"
    echo "  S3存储桶: $BUCKET_NAME"
    echo "  Lambda函数: $FUNCTION_NAME (版本 $LAMBDA_VERSION)"
    echo ""
    echo "🔗 访问链接:"
    echo "  主页: https://$CLOUDFRONT_DOMAIN/"
    echo "  Website1: https://$CLOUDFRONT_DOMAIN/website1/"
    echo "  Website2: https://$CLOUDFRONT_DOMAIN/website2/"
    echo "  App1: https://$CLOUDFRONT_DOMAIN/app1/"
    echo ""
    echo "🧪 404重定向测试:"
    echo "  https://$CLOUDFRONT_DOMAIN/website1/missing-page"
    echo "  https://$CLOUDFRONT_DOMAIN/website2/non-existent"
    echo "  https://$CLOUDFRONT_DOMAIN/app1/404-test"
    echo ""
    echo "📝 注意事项:"
    echo "- CloudFront全球部署需要10-15分钟"
    echo "- 如果访问失败，请稍后重试"
    echo "- 运行测试: ./scripts/test.sh $CLOUDFRONT_DOMAIN"
    echo ""
    echo "💾 部署信息已保存到 deployment-info.json"
}

# 主函数
main() {
    echo "🚀 微前端404重定向PoC系统部署"
    echo "=================================================="
    echo ""
    
    check_prerequisites
    setup_variables
    create_s3_bucket
    create_oai
    deploy_lambda_edge
    create_cloudfront_distribution
    wait_for_deployment
    save_deployment_info
    show_deployment_result
    
    echo ""
    echo "🎊 部署脚本执行完成！"
}

# 执行主函数
main "$@"
