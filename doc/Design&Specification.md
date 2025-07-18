# 设计与规格文档 - 细节怎么做 + 整体怎么做

## 1. 整体架构设计

### 1.1 系统架构
```
用户浏览器 → CloudFront → Lambda@Edge → S3存储桶
     ↓           ↓            ↓           ↓
   HTTP请求   CDN缓存    404处理逻辑   静态文件
```

### 1.2 核心组件职责
- **CloudFront**：全球CDN分发，触发Lambda@Edge函数，提供HTTPS和缓存
- **Lambda@Edge**：在边缘节点处理404响应，执行重定向逻辑
- **S3**：静态文件托管，提供网站内容存储

### 1.3 技术选型理由
- **Lambda@Edge**：边缘计算实现低延迟响应，全球分布式处理
- **CloudFront**：全球分发网络，内置DDoS防护，成本效益高
- **S3**：高可用性静态托管，与CloudFront深度集成

## 2. 详细技术规格

### 2.1 Lambda@Edge函数规格

#### 触发配置
- **事件类型**：Origin Response
- **触发条件**：HTTP状态码 = 404
- **执行位置**：全球边缘节点
- **执行时机**：S3返回404响应后，CloudFront返回给用户前

#### 函数配置参数
- **运行时**：Node.js 18.x
- **内存分配**：128MB
- **超时时间**：5秒
- **部署区域**：us-east-1（Lambda@Edge强制要求）
- **代码大小限制**：1MB（压缩后）

#### 重定向逻辑规格
```javascript
// 重定向规则映射表
const REDIRECT_RULES = {
    'website1': '/website1/index.html',
    'website2': '/website2/index.html',
    'app1': '/app1/index.html'
};

// 处理流程规格
1. 检查响应状态码是否为404
2. 提取请求URI的第一级路径段
3. 在映射表中查找对应的重定向目标
4. 返回302重定向响应或原始404响应
```

#### 错误处理规格
- **异常捕获**：所有异常必须被捕获，避免中断服务
- **降级策略**：发生错误时返回原始404响应
- **日志记录**：记录所有重定向事件和错误信息

### 2.2 S3存储规格

#### 目录结构规范
```
s3-bucket/
├── index.html              # 全局首页
├── website1/
│   └── index.html         # 子应用1首页
├── website2/
│   └── index.html         # 子应用2首页
└── app1/
    └── index.html         # 子应用3首页
```

#### 存储桶配置规格
- **静态网站托管**：启用，设置index.html为默认文档
- **公开访问**：禁用，仅通过CloudFront访问
- **CORS配置**：允许GET和HEAD方法，支持所有来源
- **版本控制**：禁用（PoC阶段不需要）

#### 访问控制规格
- **Origin Access Identity (OAI)**：创建专用OAI限制直接S3访问
- **存储桶策略**：仅允许CloudFront通过OAI访问
- **IAM权限**：最小权限原则，仅授予必要的读取权限

### 2.3 CloudFront分发规格

#### 缓存策略规格
```yaml
HTML文件缓存策略:
  - 路径模式: "*.html"
  - 缓存策略: CachingDisabled
  - TTL: 0秒
  - 原因: 确保内容实时性，支持快速更新

静态资源缓存策略:
  - 路径模式: "/*/assets/*", "*.css", "*.js", "*.png", "*.jpg"
  - 缓存策略: CachingOptimized
  - TTL: 31536000秒 (1年)
  - 原因: 提升性能，减少源站请求
```

#### 行为配置规格
- **默认行为**：关联Lambda@Edge函数到Origin Response事件
- **协议策略**：强制HTTPS重定向，禁用HTTP访问
- **压缩**：启用Gzip和Brotli压缩
- **HTTP版本**：支持HTTP/2

#### 安全配置规格
- **SSL证书**：使用CloudFront默认证书
- **安全头部**：通过Lambda@Edge添加基本安全头部
- **访问日志**：启用CloudFront访问日志（可选）

## 3. 数据流设计

### 3.1 正常访问流程
```
1. 用户请求 /website1/index.html
2. CloudFront检查边缘缓存
3. 缓存未命中，转发请求到S3源站
4. S3返回文件内容和200状态码
5. CloudFront缓存内容并返回给用户
6. 后续相同请求直接从缓存返回
```

### 3.2 404重定向流程
```
1. 用户请求 /website1/missing-page
2. CloudFront转发请求到S3源站
3. S3返回404状态码和错误响应
4. Lambda@Edge函数在Origin Response事件被触发
5. 函数解析URI路径，查找重定向规则
6. 返回302重定向响应，Location指向 /website1/index.html
7. 用户浏览器接收302响应，自动跳转到目标页面
```

### 3.3 错误处理流程
```
1. Lambda@Edge函数执行过程中发生异常
2. 异常被try-catch捕获并记录到CloudWatch日志
3. 函数返回原始404响应，不中断服务
4. 用户看到标准404错误页面
5. 运维人员通过日志分析和修复问题
```

## 4. 安全设计规格

### 4.1 访问控制安全
- **S3存储桶**：禁止公开访问，仅通过OAI访问
- **CloudFront**：强制HTTPS，禁用不安全的HTTP协议
- **Lambda@Edge**：使用最小权限IAM角色，仅授予必要权限

### 4.2 内容安全规格
- **输入验证**：验证URI格式，防止路径遍历攻击
- **输出编码**：确保重定向URL格式正确，防止开放重定向
- **日志安全**：不记录敏感信息，如用户IP的完整信息

### 4.3 网络安全规格
- **DDoS防护**：CloudFront内置AWS Shield Standard防护
- **Rate Limiting**：通过Lambda@Edge实现基本的请求频率限制
- **安全头部**：添加基本的安全响应头部

## 5. 性能设计规格

### 5.1 响应时间要求
- **重定向响应时间**：< 500ms（包含网络延迟）
- **Lambda@Edge执行时间**：< 100ms
- **CloudFront缓存命中响应**：< 50ms
- **S3源站响应时间**：< 200ms

### 5.2 并发处理规格
- **目标并发用户**：10个并发用户
- **峰值处理能力**：50个并发请求
- **自动扩展**：Lambda@Edge自动扩展，无需配置

### 5.3 性能优化策略
- **代码优化**：最小化函数代码体积，避免复杂计算
- **缓存优化**：合理设置TTL值，提高缓存命中率
- **网络优化**：启用HTTP/2和压缩，减少传输时间

## 6. 监控设计规格

### 6.1 关键指标定义
- **Lambda@Edge指标**：
  - 执行次数：每分钟函数调用次数
  - 错误率：错误次数/总执行次数
  - 执行时间：平均、P50、P95、P99执行时间
  - 内存使用：峰值和平均内存使用量

- **CloudFront指标**：
  - 请求数量：每分钟总请求数
  - 错误率：4xx和5xx错误率
  - 缓存命中率：缓存命中次数/总请求次数
  - 响应时间：平均响应时间分布

### 6.2 日志规范
```javascript
// 标准日志格式规范
{
    "timestamp": "2025-07-08T12:00:00.000Z",
    "event": "redirect|404_detected|function_error",
    "originalUri": "/website1/missing-page",
    "redirectPath": "/website1/index.html",
    "userAgent": "Mozilla/5.0...",
    "region": "us-east-1",
    "executionTime": 45
}
```

### 6.3 告警规范
- **高错误率告警**：错误率 > 5%，持续5分钟触发
- **高延迟告警**：平均执行时间 > 1秒，持续5分钟触发
- **成本异常告警**：日成本超过预算20%触发

## 7. 扩展性设计

### 7.1 水平扩展规格
- **添加新子应用**：在REDIRECT_RULES中添加新映射规则
- **配置管理**：当前硬编码，后续可考虑外部配置存储
- **版本管理**：通过Lambda版本控制配置变更

### 7.2 垂直扩展规格
- **内存调整**：根据实际使用情况调整Lambda内存分配
- **超时调整**：根据处理复杂度调整超时时间
- **并发限制**：设置合理的并发执行限制

### 7.3 架构演进规格
- **CloudFront Functions**：考虑将简单逻辑迁移到更轻量的CF Functions
- **动态配置**：集成DynamoDB或S3实现动态配置管理
- **多区域部署**：支持多区域Lambda@Edge部署

## 8. 成本设计规格

### 8.1 成本组成分析
- **CloudFront成本**：
  - 数据传输费用：$0.085/GB（美国/欧洲）
  - 请求费用：$0.0075/10,000个请求
  
- **Lambda@Edge成本**：
  - 请求费用：$0.60/1,000,000个请求
  - 执行时间费用：$0.00005001/GB-秒
  
- **S3成本**：
  - 存储费用：$0.023/GB/月
  - 请求费用：$0.0004/1,000个GET请求

### 8.2 成本优化策略
- **缓存优化**：提高缓存命中率，减少源站请求
- **函数优化**：减少执行时间，降低计算成本
- **传输优化**：启用压缩，减少数据传输量
- **日志管理**：设置合理的日志保留期，控制存储成本

### 8.3 预期成本估算（月度）
```
基于1000次/天的测试流量：
- CloudFront: $1-2
- Lambda@Edge: $0.5-1
- S3: $0.1-0.5
- CloudWatch: $0.1-0.3
总计: < $5/月
```

---

**文档版本**：v1.0  
**创建日期**：2025-07-08  
**专注领域**：技术架构设计和详细规格
