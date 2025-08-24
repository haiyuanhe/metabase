-- PostgreSQL RLS (Row Level Security) 设置示例
-- 用于配合Metabase embedding参数注入实现用户级数据权限

-- 1. 创建示例表
CREATE TABLE sales_data (
    id SERIAL PRIMARY KEY,
    customer_id VARCHAR(50) NOT NULL,
    region VARCHAR(50) NOT NULL,
    product_name VARCHAR(100) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    sale_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 插入示例数据
INSERT INTO sales_data (customer_id, region, product_name, amount, sale_date) VALUES
('CUST001', 'North', 'Product A', 1000.00, '2024-01-15'),
('CUST002', 'South', 'Product B', 1500.00, '2024-01-16'),
('CUST003', 'North', 'Product A', 800.00, '2024-01-17'),
('CUST004', 'East', 'Product C', 2000.00, '2024-01-18'),
('CUST005', 'West', 'Product B', 1200.00, '2024-01-19');

-- 2. 启用RLS
ALTER TABLE sales_data ENABLE ROW LEVEL SECURITY;

-- 3. 创建RLS策略函数
CREATE OR REPLACE FUNCTION check_user_access()
RETURNS BOOLEAN AS $$
BEGIN
    -- 检查会话变量是否存在
    IF current_setting('metabase.rls.customer_id', true) IS NOT NULL THEN
        -- 基于customer_id过滤
        RETURN sales_data.customer_id = current_setting('metabase.rls.customer_id');
    ELSIF current_setting('metabase.rls.region', true) IS NOT NULL THEN
        -- 基于region过滤
        RETURN sales_data.region = current_setting('metabase.rls.region');
    ELSIF current_setting('metabase.rls.user_role', true) = 'admin' THEN
        -- 管理员可以看到所有数据
        RETURN TRUE;
    ELSE
        -- 默认情况下拒绝访问
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 4. 创建RLS策略
CREATE POLICY sales_data_access_policy ON sales_data
    FOR SELECT
    USING (check_user_access());

-- 5. 创建用于测试的角色
CREATE ROLE metabase_user WITH LOGIN PASSWORD 'password';
GRANT CONNECT ON DATABASE your_database TO metabase_user;
GRANT USAGE ON SCHEMA public TO metabase_user;
GRANT SELECT ON sales_data TO metabase_user;

-- 6. 测试RLS策略
-- 设置会话变量并测试查询
-- SET SESSION metabase.rls.customer_id = 'CUST001';
-- SELECT * FROM sales_data;

-- SET SESSION metabase.rls.region = 'North';
-- SELECT * FROM sales_data;

-- SET SESSION metabase.rls.user_role = 'admin';
-- SELECT * FROM sales_data;

-- 7. 更复杂的RLS策略示例
-- 基于多个条件的策略
CREATE OR REPLACE FUNCTION check_advanced_user_access()
RETURNS BOOLEAN AS $$
DECLARE
    user_customer_id VARCHAR(50);
    user_region VARCHAR(50);
    user_role VARCHAR(50);
    user_permissions TEXT[];
BEGIN
    -- 获取会话变量
    user_customer_id := current_setting('metabase.rls.customer_id', true);
    user_region := current_setting('metabase.rls.region', true);
    user_role := current_setting('metabase.rls.user_role', true);
    user_permissions := string_to_array(current_setting('metabase.rls.permissions', true), ',');
    
    -- 管理员可以看到所有数据
    IF user_role = 'admin' THEN
        RETURN TRUE;
    END IF;
    
    -- 基于customer_id的精确匹配
    IF user_customer_id IS NOT NULL AND user_customer_id = sales_data.customer_id THEN
        RETURN TRUE;
    END IF;
    
    -- 基于region的匹配
    IF user_region IS NOT NULL AND user_region = sales_data.region THEN
        RETURN TRUE;
    END IF;
    
    -- 基于权限的匹配
    IF user_permissions IS NOT NULL AND 'view_all' = ANY(user_permissions) THEN
        RETURN TRUE;
    END IF;
    
    -- 默认拒绝
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- 8. 创建更复杂的策略
DROP POLICY IF EXISTS sales_data_access_policy ON sales_data;
CREATE POLICY sales_data_advanced_policy ON sales_data
    FOR SELECT
    USING (check_advanced_user_access());

-- 9. 创建视图以简化访问
CREATE VIEW sales_data_view AS
SELECT * FROM sales_data;

-- 为视图启用RLS
ALTER VIEW sales_data_view SET (security_barrier = true);

-- 10. 清理函数（可选）
-- DROP FUNCTION IF EXISTS check_user_access();
-- DROP FUNCTION IF EXISTS check_advanced_user_access();
-- DROP POLICY IF EXISTS sales_data_access_policy ON sales_data;
-- DROP POLICY IF EXISTS sales_data_advanced_policy ON sales_data;
-- DROP TABLE IF EXISTS sales_data;

-- Example PostgreSQL function that matches our parameter naming convention
-- Our code sets: metabase.rls.user_id, metabase.rls.org_id, etc.

CREATE OR REPLACE FUNCTION get_current_user_id()
RETURNS uuid AS $$
BEGIN
  RETURN(SELECT (
    coalesce(
      nullif(current_setting('metabase.rls.user_id', true), ''),  -- 使用 user_id
      coalesce(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
      )
    )
  )::uuid);
END;
$$ LANGUAGE plpgsql;

-- Alternative function for organization ID
CREATE OR REPLACE FUNCTION get_current_org_id()
RETURNS integer AS $$
BEGIN
  RETURN(SELECT (
    coalesce(
      nullif(current_setting('metabase.rls.org_id', true), '')::integer,  -- 使用 org_id
      0
    )
  ));
END;
$$ LANGUAGE plpgsql;
