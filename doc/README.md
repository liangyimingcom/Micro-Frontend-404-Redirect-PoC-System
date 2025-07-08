# 项目文档

本目录包含微前端404重定向PoC系统的详细技术文档。

## 📚 文档结构

### [Requirement.md](Requirement.md)
- **业务需求分析**
- 项目背景和目标
- 功能需求规格
- 验收标准定义

### [Design&Specification.md](Design&Specification.md)
- **技术设计规格**
- 系统架构设计
- 技术选型分析
- 详细实现规格

### [Implementation&Deployment.md](Implementation&Deployment.md)
- **实施部署指南**
- 代码实现说明
- 部署步骤详解
- 运维管理指南

## 🎯 阅读顺序

1. **首次了解项目** → 先阅读 [Requirement.md](Requirement.md)
2. **技术实现细节** → 然后阅读 [Design&Specification.md](Design&Specification.md)
3. **部署和运维** → 最后阅读 [Implementation&Deployment.md](Implementation&Deployment.md)

## 📋 快速参考

### 核心功能
- 子目录级别404重定向
- 基于AWS Lambda@Edge的边缘计算
- 全球CDN分发和缓存优化

### 技术栈
- **前端**: 静态HTML/CSS/JS
- **CDN**: AWS CloudFront
- **计算**: AWS Lambda@Edge (Node.js 18.x)
- **存储**: AWS S3
- **基础设施**: AWS CloudFormation

### 部署架构
```
用户浏览器 → CloudFront → Lambda@Edge → S3存储桶
     ↓           ↓            ↓           ↓
   HTTP请求   CDN缓存    重定向逻辑     静态文件
```

## 🔗 相关链接

- [项目主页](../README.md)
- [源代码](../src/)
- [部署脚本](../scripts/)
- [基础设施模板](../infrastructure/)

## 📝 文档维护

文档基于实际部署成功的系统编写，确保内容的准确性和实用性。

如发现文档问题或需要补充，请提交Issue或Pull Request。
