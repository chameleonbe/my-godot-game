extends Area2D
class_name Bullet #全局可识别

const WORLD_COLLISON_MASK := 1 #子弹碰撞的物理层  过滤器（二进制）

# 子弹飞行速度，单位为像素每秒
@export var speed: float = 320.0
# 子弹最大存活时间，防止永久存在
@export var max_lifetime = 20

# 子弹当前飞行方向
var direction: Vector2 = Vector2.RIGHT
#剩余存活时间，逐渐减到0，自动销毁
var remaining_lifetime: float = 0.0

# 初始化寿命并绑定 Area2D 碰撞信号
func _ready()->void:
	remaining_lifetime = max_lifetime
	area_entered.connect(_on_area_entered)# 信号机制，回调函数
	
	
#由外部在生成子弹时调用，注入初始方向
func setup(initial_direction: Vector2) -> void:#会暴露在外
	if initial_direction != Vector2.ZERO:
		direction = initial_direction.normalized()
		
	rotation = direction.angle()
	
	
#每帧先检测是否会撞上世界，再更新位置并处理超时回收
func _physics_process(delta:float) -> void:
	var current_position := global_position
	var next_position := current_position + direction * speed * delta
	
	if _will_hit_world(current_position,next_position):
		queue_free() # 标记-清除策略
		return
		
	global_position = next_position
		
		#未命中对象则也要标记清理(兜底策略)
	remaining_lifetime -= delta
	if remaining_lifetime <= 0.0:
		queue_free()


#使用射线查询飞行路径，避免子弹穿过薄墙体或零厚度边界
func _will_hit_world(from_position:Vector2,to_position:Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return false
	
	var query := PhysicsRayQueryParameters2D.create(
		from_position,
		to_position,
		WORLD_COLLISON_MASK
	)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	
	var hit_result: Dictionary = space_state.intersect_ray(query)
	return not hit_result.is_empty()
	
	
	#与 Area2D 碰撞后销毁，同时忽略其它子弹。
func _on_area_entered(area: Area2D) -> void:
	if area is Bullet:
		return
		
	queue_free()
