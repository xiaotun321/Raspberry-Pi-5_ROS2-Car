cd car_ws
colcon build --packages-select  tb6612_car_ros2

常用类型：
feat：新增功能
fix：修复问题
docs：文档修改
refactor：代码重构
test：测试相关
perf：性能优化
build：构建配置
ci：CI 配置
chore：其他维护
可以通过 Git Hook 强制检查。在仓库根目录创建 .githooks/commit-msg