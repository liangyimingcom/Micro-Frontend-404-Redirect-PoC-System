# 实施与部署文档 - 实际写代码 + 如何发布与部署

## 1. 项目结构

```
aws-cf-edge404direct_amazonqcli/
├── src/
│   ├── lambda/
│   │   └── index.js             # Lambda@Edge函数代码
│   └── static/
│       ├── index.html           # 全局首页
│       ├── website1/index.html  # 子应用1
│       ├── website2/index.html  # 子应用2
│       └── app1/index.html      # 子应用3
├── infrastructure/
│   └── template.yaml            # CloudFormation模板
├── scripts/
│   ├── deploy.sh               # 部署脚本
│   ├── test.sh                 # 测试脚本
│   └── cleanup.sh              # 清理脚本
└── doc/                        # 文档目录
```

## 2. Lambda@Edge函数代码

### 2.1 核心函数实现 (src/lambda/index.js)

```javascript
'use strict';

// 重定向规则配置
const REDIRECT_RULES = {
    'website1': '/website1/index.html',
    'website2': '/website2/index.html',
    'app1': '/app1/index.html'
};

/**
 * Lambda@Edge函数 - 处理404重定向
 * @param {Object} event - CloudFront事件对象
 * @returns {Object} 响应对象
 */
exports.handler = async (event) => {
    try {
        const request = event.Records[0].cf.request;
        const response = event.Records[0].cf.response;
        
        // 只处理404响应
        if (response.status !== '404') {
            return response;
        }
        
        // 提取请求信息
        const uri = request.uri;
        const userAgent = request.headers['user-agent'] ? 
            request.headers['user-agent'][0].value : 'unknown';
        const method = request.method;
        
        // 记录404事件
        console.log(JSON.stringify({
            timestamp: new Date().toISOString(),
            event: '404_detected',
            originalUri: uri,
            method: method,
            userAgent: userAgent
        }));
        
        // 解析路径，提取子目录
        const pathParts = uri.split('/').filter(part => part);
        
        if (pathParts.length === 0) {
            // 根路径404，返回原始响应
            console.log(JSON.stringify({
                timestamp: new Date().toISOString(),
                event: 'root_path_404',
                originalUri: uri
            }));
            return response;
        }
        
        const subdir = pathParts[0];
        const redirectPath = REDIRECT_RULES[subdir];
        
        if (redirectPath) {
            // 记录重定向事件
            console.log(JSON.stringify({
                timestamp: new Date().toISOString(),
                event: 'redirect_executed',
                originalUri: uri,
                redirectPath: redirectPath,
                subdir: subdir,
                userAgent: userAgent
            }));
            
            // 返回302重定向响应
            return {
                status: '302',
                statusDescription: 'Found',
                headers: {
                    location: [{
                        key: 'Location',
                        value: redirectPath
                    }],
                    'cache-control': [{
                        key: 'Cache-Control',
                        value: 'no-cache, no-store, must-revalidate'
                    }],
                    'x-redirect-reason': [{
                        key: 'X-Redirect-Reason',
                        value: 'micro-frontend-404-handler'
                    }]
                }
            };
        }
        
        // 无匹配规则，记录并返回原始404
        console.log(JSON.stringify({
            timestamp: new Date().toISOString(),
            event: 'no_redirect_rule',
            originalUri: uri,
            subdir: subdir,
            userAgent: userAgent
        }));
        
        return response;
        
    } catch (error) {
        // 记录错误，返回原始响应避免中断服务
        console.error(JSON.stringify({
            timestamp: new Date().toISOString(),
            event: 'function_error',
            error: error.message,
            stack: error.stack,
            originalUri: event.Records[0].cf.request.uri
        }));
        
        return event.Records[0].cf.response;
    }
};

// 导出用于测试的辅助函数
if (typeof module !== 'undefined' && module.exports) {
    module.exports.REDIRECT_RULES = REDIRECT_RULES;
}
```

## 3. 静态网站代码

### 3.1 全局首页 (src/static/index.html)

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>微前端404重定向PoC系统</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            text-align: center;
        }
        
        .header {
            margin-bottom: 40px;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            font-weight: 300;
        }
        
        .header p {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .app-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 30px;
            margin: 40px 0;
        }
        
        .app-card {
            background: rgba(255,255,255,0.1);
            padding: 40px 30px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255,255,255,0.2);
            transition: all 0.3s ease;
        }
        
        .app-card:hover {
            transform: translateY(-10px);
            background: rgba(255,255,255,0.15);
        }
        
        .app-card h3 {
            font-size: 1.8em;
            margin-bottom: 15px;
            font-weight: 400;
        }
        
        .app-card p {
            margin: 15px 0;
            opacity: 0.9;
            line-height: 1.6;
        }
        
        .app-link {
            display: inline-block;
            margin: 10px 15px;
            padding: 12px 24px;
            background: rgba(255,255,255,0.2);
            border-radius: 25px;
            text-decoration: none;
            color: white;
            transition: all 0.3s ease;
            border: 1px solid rgba(255,255,255,0.3);
        }
        
        .app-link:hover {
            background: rgba(255,255,255,0.3);
            transform: scale(1.05);
        }
        
        .test-link {
            background: rgba(255,255,255,0.1);
            border: 1px solid rgba(255,255,255,0.2);
        }
        
        .test-link:hover {
            background: rgba(255,255,255,0.2);
        }
        
        .info-section {
            margin-top: 60px;
            padding: 40px;
            background: rgba(0,0,0,0.2);
            border-radius: 15px;
            backdrop-filter: blur(5px);
        }
        
        .info-section h3 {
            font-size: 1.5em;
            margin-bottom: 20px;
            font-weight: 400;
        }
        
        .info-section p {
            line-height: 1.8;
            opacity: 0.9;
        }
        
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            background: #4CAF50;
            border-radius: 50%;
            margin-right: 8px;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }
        
        @media (max-width: 768px) {
            .header h1 {
                font-size: 2em;
            }
            
            .app-grid {
                grid-template-columns: 1fr;
                gap: 20px;
            }
            
            .app-card {
                padding: 30px 20px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>微前端404重定向PoC系统</h1>
            <p><span class="status-indicator"></span>验证AWS Lambda@Edge方案的子应用404重定向功能</p>
        </div>
        
        <div class="app-grid">
            <div class="app-card">
                <h3>Website1</h3>
                <p>企业网站风格的微前端应用<br>展示传统企业级界面设计</p>
                <a href="/website1/" class="app-link">访问应用</a>
                <a href="/website1/missing-page" class="app-link test-link">测试404重定向</a>
            </div>
            
            <div class="app-card">
                <h3>Website2</h3>
                <p>现代设计风格的微前端应用<br>展示渐变和现代UI元素</p>
                <a href="/website2/" class="app-link">访问应用</a>
                <a href="/website2/non-existent" class="app-link test-link">测试404重定向</a>
            </div>
            
            <div class="app-card">
                <h3>App1</h3>
                <p>单页应用风格的微前端应用<br>展示终端风格的界面设计</p>
                <a href="/app1/" class="app-link">访问应用</a>
                <a href="/app1/404-test" class="app-link test-link">测试404重定向</a>
            </div>
        </div>
        
        <div class="info-section">
            <h3>404重定向测试说明</h3>
            <p>
                点击上方"测试404重定向"链接，系统会检测到404错误并自动重定向到对应子应用的首页。
                这个过程通过AWS Lambda@Edge在全球边缘节点执行，确保低延迟的用户体验。
            </p>
            <p style="margin-top: 15px;">
                <strong>测试流程：</strong>访问不存在的页面 → Lambda@Edge检测404 → 自动重定向到子应用首页
            </p>
        </div>
    </div>
    
    <script>
        // 简单的页面加载统计
        console.log('微前端404重定向PoC系统已加载');
        console.log('页面加载时间:', performance.now().toFixed(2) + 'ms');
        
        // 添加点击统计
        document.addEventListener('click', function(e) {
            if (e.target.tagName === 'A') {
                console.log('链接点击:', e.target.href);
                
                // 如果是测试404链接，给用户提示
                if (e.target.classList.contains('test-link')) {
                    setTimeout(() => {
                        console.log('这是一个404测试链接，将会重定向到对应子应用首页');
                    }, 100);
                }
            }
        });
    </script>
</body>
</html>
```
### 3.2 子应用示例 (src/static/website1/index.html)

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Website1 - 微前端子应用</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: #f8f9fa;
            color: #333;
            line-height: 1.6;
        }
        
        .header {
            background: linear-gradient(135deg, #4CAF50, #45a049);
            color: white;
            padding: 60px 20px;
            text-align: center;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            font-weight: 300;
        }
        
        .header p {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .container {
            max-width: 1000px;
            margin: 40px auto;
            padding: 0 20px;
        }
        
        .card {
            background: white;
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
            margin: 30px 0;
            border-left: 5px solid #4CAF50;
        }
        
        .card h2 {
            color: #2e7d32;
            margin-bottom: 20px;
            font-weight: 400;
        }
        
        .card h3 {
            color: #388e3c;
            margin: 25px 0 15px 0;
            font-weight: 400;
        }
        
        .test-links {
            background: linear-gradient(135deg, #e8f5e8, #f1f8e9);
            border-left-color: #4CAF50;
        }
        
        .test-links ul {
            list-style: none;
            padding: 0;
        }
        
        .test-links li {
            margin: 15px 0;
        }
        
        .test-links a {
            display: inline-block;
            color: #2e7d32;
            text-decoration: none;
            padding: 12px 20px;
            border-radius: 8px;
            transition: all 0.3s ease;
            border: 2px solid transparent;
            background: rgba(76, 175, 80, 0.1);
        }
        
        .test-links a:hover {
            background: rgba(76, 175, 80, 0.2);
            border-color: #4CAF50;
            transform: translateX(5px);
        }
        
        .navigation {
            background: linear-gradient(135deg, #fff, #f8f9fa);
            border-left-color: #2196F3;
        }
        
        .navigation ul {
            list-style: none;
            padding: 0;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
        }
        
        .navigation li {
            margin: 0;
        }
        
        .navigation a {
            display: block;
            color: #1976d2;
            text-decoration: none;
            padding: 15px 20px;
            border-radius: 8px;
            transition: all 0.3s ease;
            background: rgba(33, 150, 243, 0.1);
            text-align: center;
        }
        
        .navigation a:hover {
            background: rgba(33, 150, 243, 0.2);
            transform: translateY(-2px);
        }
        
        .back-link {
            display: inline-block;
            margin-top: 30px;
            color: #666;
            text-decoration: none;
            padding: 12px 24px;
            border-radius: 25px;
            background: #f5f5f5;
            transition: all 0.3s ease;
        }
        
        .back-link:hover {
            background: #e0e0e0;
            color: #4CAF50;
        }
        
        .status-badge {
            display: inline-block;
            padding: 4px 12px;
            background: #4CAF50;
            color: white;
            border-radius: 12px;
            font-size: 0.8em;
            margin-left: 10px;
        }
        
        @media (max-width: 768px) {
            .header {
                padding: 40px 20px;
            }
            
            .header h1 {
                font-size: 2em;
            }
            
            .card {
                padding: 25px;
                margin: 20px 0;
            }
            
            .navigation ul {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Website1 微前端应用</h1>
        <p>企业网站风格的子应用示例<span class="status-badge">运行中</span></p>
    </div>
    
    <div class="container">
        <div class="card">
            <h2>欢迎来到Website1</h2>
            <p>这是一个微前端子应用示例，用于验证404重定向功能。当您访问本应用下不存在的页面时，AWS Lambda@Edge会在全球边缘节点检测到404错误，并自动重定向回到这个首页。</p>
            <p style="margin-top: 15px;">
                <strong>技术特点：</strong>
                边缘计算处理、低延迟响应、全球分布式部署
            </p>
        </div>
        
        <div class="card test-links">
            <h3>404重定向测试链接</h3>
            <p>点击以下链接测试404重定向功能，每个链接都会触发Lambda@Edge函数：</p>
            <ul>
                <li><a href="/website1/page1">📄 不存在的页面1</a></li>
                <li><a href="/website1/page2">📄 不存在的页面2</a></li>
                <li><a href="/website1/deep/nested/path">📁 深层嵌套路径</a></li>
                <li><a href="/website1/admin/panel">🔧 管理面板</a></li>
                <li><a href="/website1/api/data">🔗 API端点</a></li>
            </ul>
        </div>
        
        <div class="card navigation">
            <h3>导航到其他子应用</h3>
            <p>访问其他微前端子应用，体验不同的设计风格：</p>
            <ul>
                <li><a href="/website2/">Website2应用</a></li>
                <li><a href="/app1/">App1应用</a></li>
                <li><a href="/">返回主页</a></li>
            </ul>
        </div>
        
        <a href="/" class="back-link">← 返回主页</a>
    </div>
    
    <script>
        console.log('Website1 微前端应用已加载');
        
        // 添加点击统计和用户提示
        document.addEventListener('click', function(e) {
            if (e.target.tagName === 'A' && e.target.href.includes('/website1/')) {
                const href = e.target.href;
                if (href.includes('page1') || href.includes('page2') || 
                    href.includes('deep') || href.includes('admin') || 
                    href.includes('api')) {
                    console.log('404测试链接被点击:', href);
                    setTimeout(() => {
                        console.log('Lambda@Edge将处理404并重定向到当前页面');
                    }, 100);
                }
            }
        });
        
        // 显示页面加载信息
        window.addEventListener('load', function() {
            console.log('页面完全加载完成');
            console.log('当前URL:', window.location.href);
        });
    </script>
</body>
</html>
```

### 3.3 其他子应用代码

#### Website2 (src/static/website2/index.html)
```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Website2 - 现代设计风格</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: linear-gradient(45deg, #ff6b6b, #4ecdc4, #45b7d1);
            background-size: 400% 400%;
            animation: gradientShift 15s ease infinite;
            color: white;
            min-height: 100vh;
        }
        
        @keyframes gradientShift {
            0% { background-position: 0% 50%; }
            50% { background-position: 100% 50%; }
            100% { background-position: 0% 50%; }
        }
        
        .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 40px 20px;
            text-align: center;
        }
        
        .header {
            background: rgba(255,255,255,0.1);
            padding: 40px;
            border-radius: 20px;
            backdrop-filter: blur(10px);
            margin-bottom: 40px;
            border: 1px solid rgba(255,255,255,0.2);
        }
        
        .card {
            background: rgba(255,255,255,0.1);
            padding: 30px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            margin: 20px 0;
            border: 1px solid rgba(255,255,255,0.2);
        }
        
        .test-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        
        .test-link {
            display: block;
            padding: 15px;
            background: rgba(255,255,255,0.2);
            border-radius: 10px;
            text-decoration: none;
            color: white;
            transition: all 0.3s ease;
        }
        
        .test-link:hover {
            background: rgba(255,255,255,0.3);
            transform: scale(1.05);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Website2 微前端应用</h1>
            <p>现代渐变设计风格的子应用</p>
        </div>
        
        <div class="card">
            <h3>404重定向测试</h3>
            <div class="test-grid">
                <a href="/website2/products" class="test-link">产品页面</a>
                <a href="/website2/services" class="test-link">服务页面</a>
                <a href="/website2/about" class="test-link">关于我们</a>
                <a href="/website2/contact" class="test-link">联系方式</a>
            </div>
        </div>
        
        <div class="card">
            <a href="/" style="color: white;">← 返回主页</a>
        </div>
    </div>
</body>
</html>
```

#### App1 (src/static/app1/index.html)
```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>App1 - 终端风格应用</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: 'Courier New', monospace;
            background: #0a0a0a;
            color: #00ff00;
            padding: 20px;
            min-height: 100vh;
        }
        
        .terminal {
            background: #000;
            padding: 20px;
            border-radius: 5px;
            border: 1px solid #00ff00;
            box-shadow: 0 0 20px rgba(0,255,0,0.3);
        }
        
        .prompt { color: #ffff00; }
        .command { color: #00ffff; }
        .output { color: #00ff00; margin: 10px 0; }
        
        a {
            color: #00ffff;
            text-decoration: none;
        }
        
        a:hover {
            background: rgba(0,255,255,0.2);
            padding: 2px 4px;
        }
    </style>
</head>
<body>
    <div class="terminal">
        <div class="output">App1 Terminal Interface v1.0</div>
        <div class="output">Micro-frontend 404 redirect PoC system</div>
        <div class="output">========================================</div>
        <br>
        
        <div><span class="prompt">$</span> <span class="command">ls -la /app1/</span></div>
        <div class="output">
            drwxr-xr-x  2 user user 4096 Jul  8 12:00 .<br>
            drwxr-xr-x  5 user user 4096 Jul  8 12:00 ..<br>
            -rw-r--r--  1 user user 2048 Jul  8 12:00 index.html
        </div>
        <br>
        
        <div><span class="prompt">$</span> <span class="command">test-404-redirects</span></div>
        <div class="output">
            Testing 404 redirect functionality...<br>
            Available test endpoints:<br>
            ├── <a href="/app1/dashboard">dashboard</a><br>
            ├── <a href="/app1/settings">settings</a><br>
            ├── <a href="/app1/logs">logs</a><br>
            ├── <a href="/app1/admin">admin</a><br>
            └── <a href="/app1/api/status">api/status</a>
        </div>
        <br>
        
        <div><span class="prompt">$</span> <span class="command">navigate</span></div>
        <div class="output">
            Available applications:<br>
            ├── <a href="/website1/">website1</a><br>
            ├── <a href="/website2/">website2</a><br>
            └── <a href="/">home</a>
        </div>
        <br>
        
        <div><span class="prompt">$</span> <span class="command">_</span><span style="animation: blink 1s infinite;">█</span></div>
    </div>
    
    <style>
        @keyframes blink {
            0%, 50% { opacity: 1; }
            51%, 100% { opacity: 0; }
        }
    </style>
</body>
</html>
```

## 4. CloudFormation基础设施代码

### 4.1 完整基础设施模板 (infrastructure/template.yaml)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: '微前端404重定向PoC系统基础设施'

Parameters:
  ProjectName:
    Type: String
    Default: 'micro-frontend-404-poc'
    Description: '项目名称，用于资源命名'
    
  Environment:
    Type: String
    Default: 'dev'
    AllowedValues: ['dev', 'test', 'prod']
    Description: '环境名称'

Resources:
  # S3存储桶
  S3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub '${ProjectName}-${Environment}-${AWS::AccountId}-${AWS::Region}'
      WebsiteConfiguration:
        IndexDocument: 'index.html'
        ErrorDocument: 'error.html'
      PublicAccessBlockConfiguration:
        BlockPublicAcls: false
        BlockPublicPolicy: false
        IgnorePublicAcls: false
        RestrictPublicBuckets: false
      CorsConfiguration:
        CorsRules:
          - AllowedHeaders: ['*']
            AllowedMethods: ['GET', 'HEAD']
            AllowedOrigins: ['*']
            MaxAge: 3600
      NotificationConfiguration:
        CloudWatchConfigurations:
          - Event: 's3:ObjectCreated:*'
            CloudWatchConfiguration:
              LogGroupName: !Sub '/aws/s3/${ProjectName}-${Environment}'
      Tags:
        - Key: 'Project'
          Value: !Ref ProjectName
        - Key: 'Environment'
          Value: !Ref Environment

  # Origin Access Identity
  OriginAccessIdentity:
    Type: AWS::CloudFront::OriginAccessIdentity
    Properties:
      OriginAccessIdentityConfig:
        Comment: !Sub 'OAI for ${ProjectName}-${Environment}'

  # S3存储桶策略
  S3BucketPolicy:
    Type: AWS::S3::BucketPolicy
    Properties:
      Bucket: !Ref S3Bucket
      PolicyDocument:
        Statement:
          - Sid: 'AllowCloudFrontAccess'
            Effect: Allow
            Principal:
              AWS: !Sub 'arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${OriginAccessIdentity}'
            Action: 's3:GetObject'
            Resource: !Sub '${S3Bucket}/*'
          - Sid: 'DenyDirectAccess'
            Effect: Deny
            Principal: '*'
            Action: 's3:*'
            Resource: 
              - !Sub '${S3Bucket}/*'
              - !Ref S3Bucket
            Condition:
              StringNotEquals:
                'AWS:SourceArn': !Sub 'arn:aws:cloudfront::${AWS::AccountId}:distribution/*'

  # Lambda执行角色
  LambdaExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub '${ProjectName}-${Environment}-lambda-edge-role'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service:
                - lambda.amazonaws.com
                - edgelambda.amazonaws.com
            Action: 'sts:AssumeRole'
      ManagedPolicyArns:
        - 'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'
      Policies:
        - PolicyName: 'CloudWatchLogsPolicy'
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - 'logs:CreateLogGroup'
                  - 'logs:CreateLogStream'
                  - 'logs:PutLogEvents'
                  - 'logs:DescribeLogGroups'
                  - 'logs:DescribeLogStreams'
                Resource: 
                  - !Sub 'arn:aws:logs:*:${AWS::AccountId}:log-group:/aws/lambda/*'
      Tags:
        - Key: 'Project'
          Value: !Ref ProjectName
        - Key: 'Environment'
          Value: !Ref Environment

  # Lambda@Edge函数
  LambdaEdgeFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Sub '${ProjectName}-${Environment}-404-redirect'
      Runtime: 'nodejs18.x'
      Handler: 'index.handler'
      Role: !GetAtt LambdaExecutionRole.Arn
      Timeout: 5
      MemorySize: 128
      Code:
        ZipFile: |
          'use strict';
          exports.handler = async (event) => {
            console.log('Lambda@Edge function placeholder');
            return event.Records[0].cf.response;
          };
      Description: !Sub '微前端404重定向Lambda@Edge函数 - ${Environment}环境'
      Tags:
        - Key: 'Project'
          Value: !Ref ProjectName
        - Key: 'Environment'
          Value: !Ref Environment

  # Lambda函数版本
  LambdaFunctionVersion:
    Type: AWS::Lambda::Version
    Properties:
      FunctionName: !Ref LambdaEdgeFunction
      Description: !Sub 'Version for ${Environment} environment - ${AWS::StackName}'

  # CloudFront分发
  CloudFrontDistribution:
    Type: AWS::CloudFront::Distribution
    Properties:
      DistributionConfig:
        Comment: !Sub '${ProjectName}-${Environment} PoC Distribution'
        Enabled: true
        HttpVersion: 'http2'
        PriceClass: 'PriceClass_100'  # 仅使用美国、加拿大和欧洲
        DefaultRootObject: 'index.html'
        
        Origins:
          - Id: 'S3Origin'
            DomainName: !GetAtt S3Bucket.RegionalDomainName
            S3OriginConfig:
              OriginAccessIdentity: !Sub 'origin-access-identity/cloudfront/${OriginAccessIdentity}'
        
        DefaultCacheBehavior:
          TargetOriginId: 'S3Origin'
          ViewerProtocolPolicy: 'redirect-to-https'
          AllowedMethods: ['GET', 'HEAD', 'OPTIONS']
          CachedMethods: ['GET', 'HEAD']
          Compress: true
          CachePolicyId: '4135ea2d-6df8-44a3-9df3-4b5a84be39ad'  # CachingDisabled
          LambdaFunctionAssociations:
            - EventType: 'origin-response'
              LambdaFunctionARN: !Ref LambdaFunctionVersion
              IncludeBody: false
        
        CacheBehaviors:
          # 静态资源长期缓存
          - PathPattern: '*/assets/*'
            TargetOriginId: 'S3Origin'
            ViewerProtocolPolicy: 'redirect-to-https'
            AllowedMethods: ['GET', 'HEAD']
            CachedMethods: ['GET', 'HEAD']
            Compress: true
            CachePolicyId: '658327ea-f89d-4fab-a63d-7e88639e58f6'  # CachingOptimized
          
          # CSS/JS文件缓存
          - PathPattern: '*.css'
            TargetOriginId: 'S3Origin'
            ViewerProtocolPolicy: 'redirect-to-https'
            AllowedMethods: ['GET', 'HEAD']
            CachedMethods: ['GET', 'HEAD']
            Compress: true
            CachePolicyId: '658327ea-f89d-4fab-a63d-7e88639e58f6'
          
          - PathPattern: '*.js'
            TargetOriginId: 'S3Origin'
            ViewerProtocolPolicy: 'redirect-to-https'
            AllowedMethods: ['GET', 'HEAD']
            CachedMethods: ['GET', 'HEAD']
            Compress: true
            CachePolicyId: '658327ea-f89d-4fab-a63d-7e88639e58f6'
        
        CustomErrorResponses:
          - ErrorCode: 403
            ResponseCode: 404
            ResponsePagePath: '/index.html'
            ErrorCachingMinTTL: 0
        
        Logging:
          Bucket: !GetAtt S3Bucket.DomainName
          Prefix: 'cloudfront-logs/'
          IncludeCookies: false
        
      Tags:
        - Key: 'Project'
          Value: !Ref ProjectName
        - Key: 'Environment'
          Value: !Ref Environment

Outputs:
  S3BucketName:
    Description: 'S3存储桶名称'
    Value: !Ref S3Bucket
    Export:
      Name: !Sub '${AWS::StackName}-S3Bucket'

  S3BucketWebsiteURL:
    Description: 'S3网站端点URL'
    Value: !GetAtt S3Bucket.WebsiteURL
    Export:
      Name: !Sub '${AWS::StackName}-S3WebsiteURL'

  CloudFrontDomainName:
    Description: 'CloudFront分发域名'
    Value: !GetAtt CloudFrontDistribution.DomainName
    Export:
      Name: !Sub '${AWS::StackName}-CloudFrontDomain'

  CloudFrontDistributionId:
    Description: 'CloudFront分发ID'
    Value: !Ref CloudFrontDistribution
    Export:
      Name: !Sub '${AWS::StackName}-DistributionId'

  LambdaFunctionName:
    Description: 'Lambda@Edge函数名称'
    Value: !Ref LambdaEdgeFunction
    Export:
      Name: !Sub '${AWS::StackName}-LambdaFunction'

  LambdaFunctionArn:
    Description: 'Lambda@Edge函数ARN（包含版本）'
    Value: !Ref LambdaFunctionVersion
    Export:
      Name: !Sub '${AWS::StackName}-LambdaFunctionArn'
```
## 5. 部署脚本

### 5.1 自动化部署脚本 (scripts/deploy.sh)

```bash
#!/bin/bash
set -e

# 配置变量
STACK_NAME="micro-frontend-404-poc"
ENVIRONMENT="dev"
REGION="us-east-1"  # Lambda@Edge必须在us-east-1
PROJECT_NAME="micro-frontend-404-poc"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查前置条件
check_prerequisites() {
    log_step "检查前置条件..."
    
    # 检查AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI未安装，请先安装AWS CLI"
        exit 1
    fi
    
    # 检查AWS配置
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI未配置或权限不足，请运行 'aws configure'"
        exit 1
    fi
    
    # 检查Node.js（如果需要本地测试）
    if command -v node &> /dev/null; then
        log_info "Node.js版本: $(node --version)"
    else
        log_warn "Node.js未安装，跳过本地测试功能"
    fi
    
    # 检查必要文件
    if [ ! -f "infrastructure/template.yaml" ]; then
        log_error "CloudFormation模板文件不存在: infrastructure/template.yaml"
        exit 1
    fi
    
    if [ ! -f "src/lambda/index.js" ]; then
        log_error "Lambda函数文件不存在: src/lambda/index.js"
        exit 1
    fi
    
    log_info "前置条件检查通过"
}

# 获取栈输出值
get_stack_output() {
    local output_key=$1
    aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

# 部署CloudFormation栈
deploy_stack() {
    log_step "部署CloudFormation栈: $STACK_NAME"
    
    # 检查栈是否存在
    if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null; then
        log_info "更新现有栈..."
        aws cloudformation update-stack \
            --stack-name $STACK_NAME \
            --template-body file://infrastructure/template.yaml \
            --parameters ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME \
                        ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
            --capabilities CAPABILITY_NAMED_IAM \
            --region $REGION
        
        log_info "等待栈更新完成..."
        aws cloudformation wait stack-update-complete \
            --stack-name $STACK_NAME \
            --region $REGION
    else
        log_info "创建新栈..."
        aws cloudformation create-stack \
            --stack-name $STACK_NAME \
            --template-body file://infrastructure/template.yaml \
            --parameters ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME \
                        ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
            --capabilities CAPABILITY_NAMED_IAM \
            --region $REGION
        
        log_info "等待栈创建完成..."
        aws cloudformation wait stack-create-complete \
            --stack-name $STACK_NAME \
            --region $REGION
    fi
    
    log_info "CloudFormation栈部署完成"
}

# 上传静态文件到S3
upload_static_files() {
    local bucket_name=$1
    
    log_step "上传静态文件到S3存储桶: $bucket_name"
    
    if [ ! -d "src/static" ]; then
        log_error "静态文件目录不存在: src/static"
        exit 1
    fi
    
    # 上传HTML文件（不缓存）
    log_info "上传HTML文件..."
    find src/static -name "*.html" -type f | while read file; do
        relative_path=${file#src/static/}
        aws s3 cp "$file" "s3://$bucket_name/$relative_path" \
            --cache-control "no-cache, no-store, must-revalidate" \
            --content-type "text/html; charset=utf-8" \
            --region $REGION
    done
    
    # 上传其他文件（长期缓存）
    log_info "上传其他静态资源..."
    find src/static -not -name "*.html" -type f | while read file; do
        relative_path=${file#src/static/}
        aws s3 cp "$file" "s3://$bucket_name/$relative_path" \
            --cache-control "public, max-age=31536000" \
            --region $REGION
    done
    
    log_info "静态文件上传完成"
}

# 更新Lambda@Edge函数
update_lambda_function() {
    local function_name=$1
    
    log_step "更新Lambda@Edge函数: $function_name"
    
    # 创建函数包
    cd src/lambda
    log_info "创建函数部署包..."
    zip -r function.zip index.js > /dev/null
    
    # 更新函数代码
    log_info "更新函数代码..."
    aws lambda update-function-code \
        --function-name $function_name \
        --zip-file fileb://function.zip \
        --region $REGION > /dev/null
    
    # 等待函数更新完成
    log_info "等待函数更新完成..."
    aws lambda wait function-updated \
        --function-name $function_name \
        --region $REGION
    
    # 发布新版本
    log_info "发布新版本..."
    local new_version=$(aws lambda publish-version \
        --function-name $function_name \
        --region $REGION \
        --query 'Version' \
        --output text)
    
    log_info "Lambda@Edge函数更新完成，新版本: $new_version"
    
    # 清理临时文件
    rm -f function.zip
    cd ../../
    
    echo $new_version
}

# 等待CloudFront分发部署完成
wait_for_cloudfront() {
    local distribution_id=$1
    
    log_step "等待CloudFront分发部署完成..."
    log_warn "这可能需要10-15分钟，请耐心等待..."
    
    # 显示进度
    local start_time=$(date +%s)
    while true; do
        local status=$(aws cloudfront get-distribution \
            --id $distribution_id \
            --region $REGION \
            --query 'Distribution.Status' \
            --output text)
        
        if [ "$status" = "Deployed" ]; then
            break
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local minutes=$((elapsed / 60))
        local seconds=$((elapsed % 60))
        
        printf "\r等待中... 已用时: %02d:%02d (状态: %s)" $minutes $seconds $status
        sleep 30
    done
    
    echo ""
    log_info "CloudFront分发部署完成"
}

# 运行部署后测试
run_post_deploy_tests() {
    local cloudfront_domain=$1
    
    log_step "运行部署后基本测试..."
    
    # 等待一段时间让分发完全生效
    log_info "等待30秒让分发完全生效..."
    sleep 30
    
    # 测试主页
    log_info "测试主页访问..."
    local status=$(curl -s -o /dev/null -w "%{http_code}" "https://$cloudfront_domain/" || echo "000")
    if [ "$status" = "200" ]; then
        log_info "✅ 主页访问测试通过"
    else
        log_warn "⚠️  主页访问测试失败 (HTTP $status)"
    fi
    
    # 测试子应用
    log_info "测试子应用访问..."
    for app in "website1" "website2" "app1"; do
        local status=$(curl -s -o /dev/null -w "%{http_code}" "https://$cloudfront_domain/$app/" || echo "000")
        if [ "$status" = "200" ]; then
            log_info "✅ $app 访问测试通过"
        else
            log_warn "⚠️  $app 访问测试失败 (HTTP $status)"
        fi
    done
    
    log_info "基本测试完成"
    log_info "详细测试请运行: ./scripts/test.sh $cloudfront_domain"
}

# 显示部署信息
show_deployment_info() {
    local cloudfront_domain=$1
    local bucket_name=$2
    local function_name=$3
    local distribution_id=$4
    
    log_step "部署信息汇总"
    
    echo ""
    echo "🎉 部署成功完成！"
    echo ""
    echo "📋 部署信息:"
    echo "  CloudFront域名: https://$cloudfront_domain"
    echo "  S3存储桶: $bucket_name"
    echo "  Lambda函数: $function_name"
    echo "  分发ID: $distribution_id"
    echo "  部署时间: $(date)"
    echo ""
    echo "🔗 访问链接:"
    echo "  主页: https://$cloudfront_domain/"
    echo "  Website1: https://$cloudfront_domain/website1/"
    echo "  Website2: https://$cloudfront_domain/website2/"
    echo "  App1: https://$cloudfront_domain/app1/"
    echo ""
    echo "🧪 404重定向测试链接:"
    echo "  https://$cloudfront_domain/website1/missing-page"
    echo "  https://$cloudfront_domain/website2/non-existent"
    echo "  https://$cloudfront_domain/app1/404-test"
    echo ""
    echo "💡 提示:"
    echo "  - CloudFront分发可能需要额外几分钟才能完全生效"
    echo "  - 运行 './scripts/test.sh $cloudfront_domain' 进行完整测试"
    echo "  - 运行 './scripts/cleanup.sh' 清理所有资源"
    echo ""
}

# 保存部署信息
save_deployment_info() {
    local cloudfront_domain=$1
    local bucket_name=$2
    local function_name=$3
    local distribution_id=$4
    
    cat > deployment-info.json << EOF
{
  "deploymentTime": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "stackName": "$STACK_NAME",
  "environment": "$ENVIRONMENT",
  "region": "$REGION",
  "cloudFrontDomain": "$cloudfront_domain",
  "s3Bucket": "$bucket_name",
  "lambdaFunction": "$function_name",
  "distributionId": "$distribution_id",
  "urls": {
    "home": "https://$cloudfront_domain/",
    "website1": "https://$cloudfront_domain/website1/",
    "website2": "https://$cloudfront_domain/website2/",
    "app1": "https://$cloudfront_domain/app1/"
  },
  "testUrls": {
    "website1_404": "https://$cloudfront_domain/website1/missing-page",
    "website2_404": "https://$cloudfront_domain/website2/non-existent",
    "app1_404": "https://$cloudfront_domain/app1/404-test"
  }
}
EOF
    
    log_info "部署信息已保存到 deployment-info.json"
}

# 主函数
main() {
    echo "🚀 开始部署微前端404重定向PoC系统..."
    echo ""
    
    # 检查前置条件
    check_prerequisites
    
    # 部署CloudFormation栈
    deploy_stack
    
    # 获取部署信息
    log_step "获取部署信息..."
    local bucket_name=$(get_stack_output "S3BucketName")
    local cloudfront_domain=$(get_stack_output "CloudFrontDomainName")
    local function_name=$(get_stack_output "LambdaFunctionName")
    local distribution_id=$(get_stack_output "CloudFrontDistributionId")
    
    if [ -z "$bucket_name" ] || [ -z "$cloudfront_domain" ] || [ -z "$function_name" ]; then
        log_error "无法获取栈输出信息，请检查CloudFormation栈状态"
        exit 1
    fi
    
    # 上传静态文件
    upload_static_files $bucket_name
    
    # 更新Lambda@Edge函数
    local new_version=$(update_lambda_function $function_name)
    
    # 等待CloudFront分发部署完成
    if [ ! -z "$distribution_id" ]; then
        wait_for_cloudfront $distribution_id
    fi
    
    # 运行部署后测试
    run_post_deploy_tests $cloudfront_domain
    
    # 保存部署信息
    save_deployment_info $cloudfront_domain $bucket_name $function_name $distribution_id
    
    # 显示部署信息
    show_deployment_info $cloudfront_domain $bucket_name $function_name $distribution_id
}

# 错误处理
trap 'log_error "部署过程中发生错误，请检查上述日志信息"; exit 1' ERR

# 执行主函数
main "$@"
```

### 5.2 测试脚本 (scripts/test.sh)

```bash
#!/bin/bash

DOMAIN=$1
VERBOSE=${2:-false}

if [ -z "$DOMAIN" ]; then
    echo "使用方法: $0 <cloudfront-domain> [verbose]"
    echo "示例: $0 d1234567890123.cloudfront.net"
    echo "      $0 d1234567890123.cloudfront.net verbose"
    exit 1
fi

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 日志函数
log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
}

log_info() {
    if [ "$VERBOSE" = "verbose" ]; then
        echo -e "${YELLOW}[INFO]${NC} $1"
    fi
}

# 测试HTTP状态码
test_http_status() {
    local url=$1
    local expected_status=$2
    local description=$3
    
    ((TOTAL_TESTS++))
    log_test "$description"
    
    local response=$(curl -s -I "https://$url" 2>/dev/null)
    local status=$(echo "$response" | grep "HTTP" | awk '{print $2}' | head -1)
    
    log_info "请求URL: https://$url"
    log_info "期望状态: $expected_status"
    log_info "实际状态: $status"
    
    if [ "$status" = "$expected_status" ]; then
        log_pass "$description - HTTP $status"
    else
        log_fail "$description - HTTP $status (期望 $expected_status)"
        if [ "$VERBOSE" = "verbose" ]; then
            echo "$response" | head -10
        fi
    fi
}

# 测试重定向
test_redirect() {
    local path=$1
    local expected_location=$2
    local description=$3
    
    ((TOTAL_TESTS++))
    log_test "$description"
    
    local response=$(curl -s -I "https://$DOMAIN$path" 2>/dev/null)
    local status=$(echo "$response" | grep "HTTP" | awk '{print $2}' | head -1)
    local location=$(echo "$response" | grep -i "location:" | awk '{print $2}' | tr -d '\r' | head -1)
    
    log_info "请求路径: $path"
    log_info "期望重定向: $expected_location"
    log_info "实际状态: $status"
    log_info "实际位置: $location"
    
    if [ "$status" = "302" ] && [[ "$location" == *"$expected_location"* ]]; then
        log_pass "$description - 302 → $expected_location"
    else
        log_fail "$description - HTTP $status, Location: $location"
        if [ "$VERBOSE" = "verbose" ]; then
            echo "$response" | head -10
        fi
    fi
}

# 测试响应时间
test_response_time() {
    local url=$1
    local max_time=$2
    local description=$3
    
    ((TOTAL_TESTS++))
    log_test "$description"
    
    local start_time=$(date +%s%N)
    local status=$(curl -s -o /dev/null -w "%{http_code}" "https://$url" 2>/dev/null)
    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 ))
    
    log_info "响应时间: ${duration}ms"
    log_info "最大允许: ${max_time}ms"
    
    if [ $duration -lt $max_time ]; then
        log_pass "$description - ${duration}ms < ${max_time}ms"
    else
        log_fail "$description - ${duration}ms >= ${max_time}ms"
    fi
}

# 测试内容验证
test_content() {
    local url=$1
    local expected_content=$2
    local description=$3
    
    ((TOTAL_TESTS++))
    log_test "$description"
    
    local content=$(curl -s "https://$url" 2>/dev/null)
    
    if [[ "$content" == *"$expected_content"* ]]; then
        log_pass "$description - 内容包含预期文本"
    else
        log_fail "$description - 内容不包含预期文本"
        if [ "$VERBOSE" = "verbose" ]; then
            echo "预期内容: $expected_content"
            echo "实际内容前100字符: ${content:0:100}..."
        fi
    fi
}

# 显示测试开始信息
echo "🧪 开始测试微前端404重定向PoC系统"
echo "目标域名: $DOMAIN"
echo "详细模式: $VERBOSE"
echo "开始时间: $(date)"
echo ""

# 1. 基本页面访问测试
echo "1️⃣ 基本页面访问测试"
test_http_status "$DOMAIN/" "200" "主页访问"
test_http_status "$DOMAIN/website1/" "200" "Website1访问"
test_http_status "$DOMAIN/website2/" "200" "Website2访问"
test_http_status "$DOMAIN/app1/" "200" "App1访问"
echo ""

# 2. 内容验证测试
echo "2️⃣ 内容验证测试"
test_content "$DOMAIN/" "微前端404重定向PoC系统" "主页内容验证"
test_content "$DOMAIN/website1/" "Website1 微前端应用" "Website1内容验证"
test_content "$DOMAIN/website2/" "Website2 微前端应用" "Website2内容验证"
test_content "$DOMAIN/app1/" "App1 Terminal Interface" "App1内容验证"
echo ""

# 3. 404重定向功能测试
echo "3️⃣ 404重定向功能测试"
test_redirect "/website1/missing-page" "/website1/index.html" "Website1重定向"
test_redirect "/website1/page1" "/website1/index.html" "Website1页面1重定向"
test_redirect "/website1/deep/nested/path" "/website1/index.html" "Website1深层路径重定向"
test_redirect "/website2/non-existent" "/website2/index.html" "Website2重定向"
test_redirect "/website2/products" "/website2/index.html" "Website2产品页重定向"
test_redirect "/app1/404-test" "/app1/index.html" "App1重定向"
test_redirect "/app1/dashboard" "/app1/index.html" "App1仪表板重定向"
echo ""

# 4. 边界情况测试
echo "4️⃣ 边界情况测试"
test_http_status "$DOMAIN/unknown/path" "404" "未知路径404"
test_http_status "$DOMAIN/nonexistent-file.html" "404" "根目录不存在文件"
test_http_status "$DOMAIN/favicon.ico" "404" "不存在的favicon"
echo ""

# 5. 性能测试
echo "5️⃣ 性能测试"
test_response_time "$DOMAIN/" 1000 "主页响应时间"
test_response_time "$DOMAIN/website1/" 1000 "Website1响应时间"
test_response_time "$DOMAIN/website1/missing-page" 1500 "404重定向响应时间"
echo ""

# 6. 安全测试
echo "6️⃣ 安全测试"
test_http_status "$DOMAIN" "301" "HTTP到HTTPS重定向"
# 测试是否有安全头部
((TOTAL_TESTS++))
log_test "安全头部检查"
local headers=$(curl -s -I "https://$DOMAIN/" 2>/dev/null)
if [[ "$headers" == *"X-Redirect-Reason"* ]]; then
    log_pass "安全头部检查 - 找到自定义头部"
else
    log_fail "安全头部检查 - 未找到预期的安全头部"
fi
echo ""

# 7. 并发测试（简单版本）
echo "7️⃣ 并发测试"
((TOTAL_TESTS++))
log_test "并发访问测试"
local concurrent_requests=5
local success_count=0

for i in $(seq 1 $concurrent_requests); do
    (
        status=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/" 2>/dev/null)
        if [ "$status" = "200" ]; then
            echo "success"
        fi
    ) &
done

wait
success_count=$(jobs | grep -c "success" || echo "0")

if [ $success_count -ge $((concurrent_requests / 2)) ]; then
    log_pass "并发访问测试 - $success_count/$concurrent_requests 请求成功"
else
    log_fail "并发访问测试 - 只有 $success_count/$concurrent_requests 请求成功"
fi
echo ""

# 测试结果汇总
echo "📊 测试结果汇总"
echo "总测试数: $TOTAL_TESTS"
echo "通过测试: $PASSED_TESTS"
echo "失败测试: $FAILED_TESTS"
echo "成功率: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
echo "完成时间: $(date)"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo "🎉 所有测试通过！PoC系统工作正常"
    exit 0
else
    echo "⚠️  有 $FAILED_TESTS 个测试失败，请检查系统状态"
    echo ""
    echo "💡 故障排除建议:"
    echo "  1. 确认CloudFront分发已完全部署（可能需要10-15分钟）"
    echo "  2. 检查Lambda@Edge函数是否正确关联到分发"
    echo "  3. 验证S3存储桶中的文件是否正确上传"
    echo "  4. 运行 'aws cloudformation describe-stacks --stack-name micro-frontend-404-poc' 检查栈状态"
    exit 1
fi
```
### 5.3 清理脚本 (scripts/cleanup.sh)

```bash
#!/bin/bash
set -e

# 配置变量
STACK_NAME="micro-frontend-404-poc"
REGION="us-east-1"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 获取栈输出值
get_stack_output() {
    local output_key=$1
    aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

# 清空S3存储桶
empty_s3_bucket() {
    local bucket_name=$1
    
    log_info "清空S3存储桶: $bucket_name"
    
    if aws s3 ls "s3://$bucket_name" &> /dev/null; then
        # 删除所有对象
        aws s3 rm "s3://$bucket_name" --recursive --region $REGION
        
        # 删除所有版本（如果启用了版本控制）
        aws s3api list-object-versions \
            --bucket $bucket_name \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text | while read key version_id; do
            if [ ! -z "$key" ] && [ ! -z "$version_id" ]; then
                aws s3api delete-object \
                    --bucket $bucket_name \
                    --key "$key" \
                    --version-id "$version_id" \
                    --region $REGION > /dev/null
            fi
        done
        
        # 删除删除标记
        aws s3api list-object-versions \
            --bucket $bucket_name \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text | while read key version_id; do
            if [ ! -z "$key" ] && [ ! -z "$version_id" ]; then
                aws s3api delete-object \
                    --bucket $bucket_name \
                    --key "$key" \
                    --version-id "$version_id" \
                    --region $REGION > /dev/null
            fi
        done
        
        log_info "S3存储桶已清空"
    else
        log_warn "S3存储桶不存在或已清空"
    fi
}

# 删除CloudFormation栈
delete_stack() {
    log_info "删除CloudFormation栈: $STACK_NAME"
    
    if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null; then
        # 获取S3存储桶名称
        local bucket_name=$(get_stack_output "S3BucketName")
        
        # 清空S3存储桶
        if [ ! -z "$bucket_name" ]; then
            empty_s3_bucket $bucket_name
        fi
        
        # 删除栈
        aws cloudformation delete-stack \
            --stack-name $STACK_NAME \
            --region $REGION
        
        log_info "等待栈删除完成..."
        aws cloudformation wait stack-delete-complete \
            --stack-name $STACK_NAME \
            --region $REGION
        
        log_info "CloudFormation栈删除完成"
    else
        log_warn "CloudFormation栈不存在"
    fi
}

# 清理本地文件
cleanup_local_files() {
    log_info "清理本地临时文件..."
    
    # 删除部署信息文件
    rm -f deployment-info.json
    rm -f deployment-info.txt
    
    # 删除Lambda函数包
    rm -f src/lambda/function.zip
    
    # 删除日志文件
    rm -f *.log
    
    log_info "本地文件清理完成"
}

# 显示清理确认
show_cleanup_warning() {
    echo "⚠️  即将删除所有PoC系统资源"
    echo ""
    echo "将要删除的资源:"
    echo "  - CloudFormation栈: $STACK_NAME"
    echo "  - S3存储桶及其所有内容"
    echo "  - CloudFront分发"
    echo "  - Lambda@Edge函数"
    echo "  - IAM角色和策略"
    echo "  - 本地临时文件"
    echo ""
    echo "⚠️  此操作不可逆！"
    echo ""
}

# 主函数
main() {
    echo "🗑️  微前端404重定向PoC系统资源清理工具"
    echo ""
    
    show_cleanup_warning
    
    # 确认删除
    read -p "确认删除所有资源？(输入 'yes' 确认): " -r
    echo ""
    
    if [[ $REPLY != "yes" ]]; then
        log_info "取消清理操作"
        exit 0
    fi
    
    log_info "开始清理PoC系统资源..."
    
    # 删除CloudFormation栈（包括S3清理）
    delete_stack
    
    # 清理本地文件
    cleanup_local_files
    
    echo ""
    log_info "✅ 清理完成！"
    echo ""
    echo "📋 清理汇总:"
    echo "  - 所有AWS资源已删除"
    echo "  - 本地临时文件已清理"
    echo "  - 不会产生额外费用"
    echo ""
    echo "💡 如需重新部署，请运行: ./scripts/deploy.sh"
}

# 错误处理
trap 'log_error "清理过程中发生错误，请检查上述日志信息"; exit 1' ERR

# 执行主函数
main "$@"
```

## 6. 快速开始指南

### 6.1 一键部署

```bash
# 1. 创建项目目录
mkdir micro-frontend-404-poc && cd micro-frontend-404-poc

# 2. 创建目录结构
mkdir -p src/{lambda,static/{website1,website2,app1}}
mkdir -p infrastructure scripts doc

# 3. 复制所有代码文件（按照上述内容创建）

# 4. 设置脚本执行权限
chmod +x scripts/*.sh

# 5. 执行一键部署
./scripts/deploy.sh
```

### 6.2 分步部署

#### 步骤1: 环境准备
```bash
# 检查AWS CLI配置
aws sts get-caller-identity

# 检查必要权限
aws iam get-user
```

#### 步骤2: 部署基础设施
```bash
# 部署CloudFormation栈
aws cloudformation deploy \
    --template-file infrastructure/template.yaml \
    --stack-name micro-frontend-404-poc \
    --capabilities CAPABILITY_NAMED_IAM \
    --region us-east-1
```

#### 步骤3: 上传静态文件
```bash
# 获取S3存储桶名称
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name micro-frontend-404-poc \
    --region us-east-1 \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

# 上传文件
aws s3 sync src/static/ s3://$BUCKET_NAME/ --region us-east-1
```

#### 步骤4: 更新Lambda函数
```bash
# 获取函数名称
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name micro-frontend-404-poc \
    --region us-east-1 \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# 打包并更新函数
cd src/lambda
zip -r function.zip index.js
aws lambda update-function-code \
    --function-name $FUNCTION_NAME \
    --zip-file fileb://function.zip \
    --region us-east-1
```

### 6.3 验证部署

#### 基本验证
```bash
# 获取CloudFront域名
DOMAIN=$(aws cloudformation describe-stacks \
    --stack-name micro-frontend-404-poc \
    --region us-east-1 \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDomainName`].OutputValue' \
    --output text)

# 测试主页
curl -I https://$DOMAIN/

# 测试404重定向
curl -I https://$DOMAIN/website1/missing-page
```

#### 完整测试
```bash
# 运行完整测试套件
./scripts/test.sh $DOMAIN verbose
```

### 6.4 监控和调试

#### 查看Lambda@Edge日志
```bash
# 列出所有日志组
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/micro-frontend-404-poc" \
    --region us-east-1

# 查看最新日志
aws logs filter-log-events \
    --log-group-name "/aws/lambda/us-east-1.micro-frontend-404-poc-dev-404-redirect" \
    --start-time $(date -d "1 hour ago" +%s)000 \
    --region us-east-1
```

#### 查看CloudFront指标
```bash
# 获取分发ID
DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
    --stack-name micro-frontend-404-poc \
    --region us-east-1 \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' \
    --output text)

# 查看分发状态
aws cloudfront get-distribution --id $DISTRIBUTION_ID --region us-east-1
```

### 6.5 故障排除

#### 常见问题

1. **Lambda@Edge部署失败**
   ```bash
   # 检查函数状态
   aws lambda get-function --function-name micro-frontend-404-poc-dev-404-redirect --region us-east-1
   ```

2. **CloudFront缓存问题**
   ```bash
   # 创建缓存失效
   aws cloudfront create-invalidation \
       --distribution-id $DISTRIBUTION_ID \
       --paths "/*" \
       --region us-east-1
   ```

3. **404重定向不工作**
   ```bash
   # 检查Lambda@Edge日志
   aws logs filter-log-events \
       --log-group-name "/aws/lambda/us-east-1.micro-frontend-404-poc-dev-404-redirect" \
       --filter-pattern "redirect" \
       --region us-east-1
   ```

#### 调试工具

```bash
# 本地测试Lambda函数
node -e "
const handler = require('./src/lambda/index.js').handler;
const event = {
  Records: [{
    cf: {
      request: { uri: '/website1/test', method: 'GET', headers: {} },
      response: { status: '404', statusDescription: 'Not Found' }
    }
  }]
};
handler(event).then(console.log);
"
```

### 6.6 清理资源

```bash
# 一键清理所有资源
./scripts/cleanup.sh

# 或手动清理
aws cloudformation delete-stack \
    --stack-name micro-frontend-404-poc \
    --region us-east-1
```

---

**文档版本**：v1.0  
**创建日期**：2025-07-08  
**专注领域**：具体代码实现和部署操作
