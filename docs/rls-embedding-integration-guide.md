# Metabase RLS + Embedding 集成指南

本指南详细说明如何通过改造Metabase实现通过embedding参数注入来支持PostgreSQL RLS的用户级数据权限方案。

## 概述

这个方案的核心思想是：
1. 在embedding请求中注入用户身份参数（以`rls_`前缀开头）
2. 在查询处理过程中，将这些参数传递给JDBC连接
3. 在PostgreSQL中通过RLS策略使用这些参数进行数据过滤

## 架构设计

```
Embedding Request
    ↓
JWT Token + URL Parameters
    ↓
RLS Parameter Extraction (rls_*)
    ↓
Query Processing Middleware
    ↓
PostgreSQL Session Variables
    ↓
RLS Policies Filter Data
```

## 实现步骤

### 1. 数据库端设置

#### 1.1 启用RLS
```sql
-- 为表启用RLS
ALTER TABLE your_table ENABLE ROW LEVEL SECURITY;
```

#### 1.2 创建RLS策略函数
```sql
CREATE OR REPLACE FUNCTION check_user_access()
RETURNS BOOLEAN AS $$
BEGIN
    -- 检查会话变量
    IF current_setting('metabase.rls.user_id', true) IS NOT NULL THEN
        RETURN your_table.user_id = current_setting('metabase.rls.user_id');
    ELSIF current_setting('metabase.rls.tenant_id', true) IS NOT NULL THEN
        RETURN your_table.tenant_id = current_setting('metabase.rls.tenant_id');
    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

#### 1.3 创建RLS策略
```sql
CREATE POLICY user_access_policy ON your_table
    FOR SELECT
    USING (check_user_access());
```

### 2. Metabase端配置

#### 2.1 创建Embedding JWT Token

在JWT token中包含RLS参数：

```javascript
const token = {
  resource: {
    question: cardId  // 或 dashboard: dashboardId
  },
  params: {
    // 普通参数
    date_range: "last_30_days",
    
    // RLS参数（以rls_开头）
    rls_user_id: "user123",
    rls_tenant_id: "tenant456",
    rls_region: "north"
  }
};
```

#### 2.2 URL参数传递

也可以通过URL参数传递RLS参数：

```
https://your-metabase.com/embed/question/token?rls_user_id=user123&rls_tenant_id=tenant456
```

### 3. 使用示例

#### 3.1 基本使用

1. **创建Dashboard/Card**：在Metabase中创建需要嵌入的Dashboard或Card

2. **启用Embedding**：
   - 进入Dashboard/Card设置
   - 启用"Embedding"
   - 配置允许的参数

3. **生成JWT Token**：
```python
import jwt
import time

payload = {
    "resource": {"question": 123},  # Card ID
    "params": {
        "rls_user_id": "user123",
        "rls_tenant_id": "tenant456"
    },
    "exp": int(time.time()) + 3600  # 1小时过期
}

token = jwt.encode(payload, "your-secret-key", algorithm="HS256")
```

4. **嵌入到应用**：
```html
<iframe 
  src="https://your-metabase.com/embed/question/token#bordered=true&titled=true"
  width="100%" 
  height="600px">
</iframe>
```

#### 3.2 动态参数传递

```javascript
// 根据当前用户动态生成embedding URL
function generateEmbeddingUrl(userId, tenantId) {
  const baseUrl = "https://your-metabase.com/embed/question/token";
  const params = new URLSearchParams({
    rls_user_id: userId,
    rls_tenant_id: tenantId
  });
  
  return `${baseUrl}?${params.toString()}`;
}

// 使用
const iframe = document.getElementById('metabase-iframe');
iframe.src = generateEmbeddingUrl(currentUser.id, currentUser.tenantId);
```

### 4. 高级配置

#### 4.1 复杂RLS策略

```sql
CREATE OR REPLACE FUNCTION advanced_user_access()
RETURNS BOOLEAN AS $$
DECLARE
    user_id VARCHAR(50);
    tenant_id VARCHAR(50);
    user_role VARCHAR(50);
    permissions TEXT[];
BEGIN
    user_id := current_setting('metabase.rls.user_id', true);
    tenant_id := current_setting('metabase.rls.tenant_id', true);
    user_role := current_setting('metabase.rls.user_role', true);
    permissions := string_to_array(current_setting('metabase.rls.permissions', true), ',');
    
    -- 管理员可以看到所有数据
    IF user_role = 'admin' THEN
        RETURN TRUE;
    END IF;
    
    -- 基于用户ID和租户ID的精确匹配
    IF user_id IS NOT NULL AND tenant_id IS NOT NULL THEN
        RETURN your_table.user_id = user_id AND your_table.tenant_id = tenant_id;
    END IF;
    
    -- 基于权限的访问
    IF permissions IS NOT NULL AND 'view_all' = ANY(permissions) THEN
        RETURN TRUE;
    END IF;
    
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;
```

#### 4.2 多租户支持

```sql
-- 为不同租户创建不同的策略
CREATE POLICY tenant_access_policy ON your_table
    FOR SELECT
    USING (
        tenant_id = current_setting('metabase.rls.tenant_id', true) OR
        current_setting('metabase.rls.user_role', true) = 'admin'
    );
```

### 5. 安全考虑

#### 5.1 JWT Token安全
- 使用强密钥
- 设置合理的过期时间
- 定期轮换密钥

#### 5.2 参数验证
- 在应用层验证RLS参数
- 防止SQL注入
- 限制参数值范围

#### 5.3 数据库安全
- 使用最小权限原则
- 定期审计RLS策略
- 监控异常访问

### 6. 故障排除

#### 6.1 常见问题

1. **RLS参数未生效**
   - 检查参数名是否以`rls_`开头
   - 确认PostgreSQL会话变量设置成功
   - 验证RLS策略函数逻辑

2. **权限被拒绝**
   - 检查数据库用户权限
   - 确认RLS策略正确配置
   - 验证会话变量值

3. **查询返回空结果**
   - 检查RLS策略条件
   - 确认数据存在且匹配条件
   - 验证参数值格式

#### 6.2 调试技巧

```sql
-- 检查当前会话变量
SELECT name, setting FROM pg_settings WHERE name LIKE 'metabase.rls.%';

-- 测试RLS策略
SET SESSION metabase.rls.user_id = 'test_user';
SELECT * FROM your_table;

-- 查看RLS策略
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies WHERE tablename = 'your_table';
```

### 7. 性能优化

#### 7.1 索引优化
```sql
-- 为RLS策略中使用的列创建索引
CREATE INDEX idx_your_table_user_id ON your_table(user_id);
CREATE INDEX idx_your_table_tenant_id ON your_table(tenant_id);
```

#### 7.2 查询优化
- 避免在RLS策略中使用复杂函数
- 使用适当的索引
- 考虑分区表

### 8. 监控和日志

#### 8.1 启用查询日志
```sql
-- 在PostgreSQL中启用查询日志
ALTER SYSTEM SET log_statement = 'all';
SELECT pg_reload_conf();
```

#### 8.2 监控RLS效果
```sql
-- 创建监控视图
CREATE VIEW rls_access_log AS
SELECT 
    current_setting('metabase.rls.user_id', true) as user_id,
    current_setting('metabase.rls.tenant_id', true) as tenant_id,
    count(*) as row_count,
    now() as access_time
FROM your_table
GROUP BY 1, 2;
```

## 总结

通过这个方案，你可以：
1. 在embedding中实现细粒度的数据权限控制
2. 利用PostgreSQL RLS的强大功能
3. 保持代码的简洁性和可维护性
4. 实现真正的多租户数据隔离

这个方案特别适合需要为不同用户提供不同数据视图的SaaS应用场景。
