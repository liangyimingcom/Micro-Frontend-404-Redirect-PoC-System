'use strict';

exports.handler = (event, context, callback) => {
    console.log('Lambda@Edge Origin Request function started');
    console.log('Event:', JSON.stringify(event, null, 2));
    
    try {
        const request = event.Records[0].cf.request;
        
        console.log('Processing request:', {
            uri: request.uri,
            method: request.method
        });
        
        // 处理子目录访问 - 直接重定向，不需要等待S3响应
        if (request.uri === '/website1/' || request.uri === '/website1') {
            console.log('Redirecting /website1/ to /website1/index.html');
            const redirectResponse = {
                status: '302',
                statusDescription: 'Found',
                headers: {
                    location: [{
                        key: 'Location',
                        value: '/website1/index.html'
                    }],
                    'cache-control': [{
                        key: 'Cache-Control',
                        value: 'no-cache'
                    }]
                }
            };
            callback(null, redirectResponse);
            return;
        }
        
        if (request.uri === '/website2/' || request.uri === '/website2') {
            console.log('Redirecting /website2/ to /website2/index.html');
            const redirectResponse = {
                status: '302',
                statusDescription: 'Found',
                headers: {
                    location: [{
                        key: 'Location',
                        value: '/website2/index.html'
                    }],
                    'cache-control': [{
                        key: 'Cache-Control',
                        value: 'no-cache'
                    }]
                }
            };
            callback(null, redirectResponse);
            return;
        }
        
        if (request.uri === '/app1/' || request.uri === '/app1') {
            console.log('Redirecting /app1/ to /app1/index.html');
            const redirectResponse = {
                status: '302',
                statusDescription: 'Found',
                headers: {
                    location: [{
                        key: 'Location',
                        value: '/app1/index.html'
                    }],
                    'cache-control': [{
                        key: 'Cache-Control',
                        value: 'no-cache'
                    }]
                }
            };
            callback(null, redirectResponse);
            return;
        }
        
        // 处理404重定向 - 检查路径模式
        if (request.uri.startsWith('/website1/') && !request.uri.endsWith('.html') && !request.uri.endsWith('.css') && !request.uri.endsWith('.js')) {
            console.log('Redirecting website1 404 to /website1/index.html');
            const redirectResponse = {
                status: '302',
                statusDescription: 'Found',
                headers: {
                    location: [{
                        key: 'Location',
                        value: '/website1/index.html'
                    }],
                    'cache-control': [{
                        key: 'Cache-Control',
                        value: 'no-cache'
                    }]
                }
            };
            callback(null, redirectResponse);
            return;
        }
        
        if (request.uri.startsWith('/website2/') && !request.uri.endsWith('.html') && !request.uri.endsWith('.css') && !request.uri.endsWith('.js')) {
            console.log('Redirecting website2 404 to /website2/index.html');
            const redirectResponse = {
                status: '302',
                statusDescription: 'Found',
                headers: {
                    location: [{
                        key: 'Location',
                        value: '/website2/index.html'
                    }],
                    'cache-control': [{
                        key: 'Cache-Control',
                        value: 'no-cache'
                    }]
                }
            };
            callback(null, redirectResponse);
            return;
        }
        
        if (request.uri.startsWith('/app1/') && !request.uri.endsWith('.html') && !request.uri.endsWith('.css') && !request.uri.endsWith('.js')) {
            console.log('Redirecting app1 404 to /app1/index.html');
            const redirectResponse = {
                status: '302',
                statusDescription: 'Found',
                headers: {
                    location: [{
                        key: 'Location',
                        value: '/app1/index.html'
                    }],
                    'cache-control': [{
                        key: 'Cache-Control',
                        value: 'no-cache'
                    }]
                }
            };
            callback(null, redirectResponse);
            return;
        }
        
        // 继续正常请求
        console.log('No redirect needed, continuing with original request');
        callback(null, request);
        
    } catch (error) {
        console.error('Error in Lambda@Edge function:', error);
        // 继续原始请求而不是返回错误
        callback(null, event.Records[0].cf.request);
    }
};
