extends CharacterBody2D
class_name Player

const NORMAL_ANIMATION_PREFIX := &"normal"#：=自动推断静态类型

const BULLET_SCENCE := preload("res://scene/bullet.tscn")  #子弹场景的载入
const ARMED_ANIMATION_PREFIX := &"armed" #强化动画名前缀
#const DEFAULT_FIRE_RATE_MULTIPLTER := 1.0 #默认开火频率
#const SPIRAL_PHASE_STEP := PI/12 #螺旋射击的旋转步长
##临时调用，查看效果
#const PickupConfig.PlayerFormMode.NORMAL := 0
#const PickupConfig.PlayerFormMode.ARMED := 1
#const SHOT_PATTERN_NORMAL := 0
#const SHOT_PATTERN_SPIRAL := 1
const DEFAULT_MOVE_SPEED_MULTIPLIER := 1.0
const DEFAULT_FIRE_RATE_MULTIPLTER := 1.0
const SPIRAL_PHASE_STEP := PI/12
const BLINK_ENABLE_SHADER_PAREMETER := &"blink_enabled"
const WORLD_COLLSION_MASK := 1

# 角色动画节点，负责播放四向动画
@onready var body_sprite: AnimatedSprite2D = $BodySprite  #Ctrl+拖拽对应节点可快速得到

# 螺旋强化状态下额外显示浮游炮特效
@onready var armed_effect_sprite: AnimatedSprite2D = $ArmedEffectSprite
# 射击计时器，只负责限制开火频率
@onready var shooting_timer: Timer = $ShootingTimer
@onready var shoot_sfx_player: AudioStreamPlayer = $AudioContainer/ShootSfxPlayer
@onready var move_sfx_player: AudioStreamPlayer = $AudioContainer/MoveSfxPlayer
@onready var pickup_sfx_player: AudioStreamPlayer = $AudioContainer/PickupSfxPlayer
@onready var s_pickup_sfx_player: AudioStreamPlayer = $AudioContainer/SPickupSfxPlayer

#当前朝向后缀，对应动画名中 up/down/left/right
var facing_suffix:StringName = &"right"

## 普通射速倍率
#var rapid_fire_rate_multiplier: float = DEFAULT_FIRE_RATE_MULTIPLTER
## 强化状态自带的射速倍率
#var form_fire_rate_multiplier: float = DEFAULT_FIRE_RATE_MULTIPLTER
## 当前玩家形态
#var current_form_mode: int = PickupConfig.PlayerFormMode.NORMAL
## 当前弹幕模式
#var current_shot_pattern: int = SHOT_PATTERN_NORMAL
## 螺旋弹幕的相位，用来让连续射击形成旋转感
#var spiral_phase: float = 0.0

# 当前移速倍率，由道具效果驱动
var current_move_speed_multiplier: float = DEFAULT_MOVE_SPEED_MULTIPLIER
# 普通射速道具提供的射速频率
var rapid_fire_rate_multiplier: float = DEFAULT_FIRE_RATE_MULTIPLTER
# 形态道具提供的专属射速倍率
var form_fire_rate_multiplier: float = DEFAULT_FIRE_RATE_MULTIPLTER
# 当前玩家状态（决定是否armed动画效果）
var current_form_mode: int = PickupConfig.PlayerFormMode.NORMAL
# 当前弹幕模式
var current_shot_pattern: int = PickupConfig.ShotPattern.NORMAL
# 三类BUFF分别维护持续时间，避免覆盖
var speed_buff_time_left: float = 0.0
var rapid_buff_time_left: float = 0.0
var form_buff_time_left: float = 0.0
# 螺旋弹幕的相位，用来让连续射击形成旋转感
var spiral_phase: float = 0.0

#玩家移动速度，单位像素/秒
@export var move_speed: float = 120.0
# 玩家最大生命值
@export var max_health: int = 5
# 受伤进入的无敌时间
@export var invincibility_duration: float = 0.5


# 玩家当前生命值
var current_health: int = 0
# 无敌剩余时间，大于零忽略伤害请求
var invincibility_time_left: float = 0.0
# 玩家死后无法攻击和移动
var is_dead: bool = false

#连续开火之间的最短间隔
@export var fire_interval: float = 0.18
#子弹生成时相对玩家的偏移距离，避免子弹在角色内部出现
@export var bullet_spawn_distance: float = 18.0  

#func _ready() -> void:#就绪时调用
	##test()  
	#shooting_timer.one_shot = true #默认循环触发
	#shooting_timer.wait_time = _get_effective_fire_interval()
	#_update_animation()
	#_update_armed_effect()
func _ready() -> void:
	current_health = maxi(max_health,1)
	shooting_timer.one_shot = true #默认循环触发
	shooting_timer.wait_time = _get_effective_fire_interval()
	_set_hurt_blink_enabled(false)
	_update_animation()
	_update_armed_effect()
	
func _physics_process(delta: float) -> void:
	_update_invincibility(delta)
	_update_pickup_effects(delta)  #更新道具效果
	
	if is_dead:
		velocity =Vector2.ZERO
		_set_move_sfx_active(false)
		return
	
	#读取四个方向输入，并得到标准化八向输入向量
	var move_input := Input.get_vector("move_left","move_right","move_up","move_down")
	var shoot_input := Input.get_vector("shoot_left","shoot_right","shoot_up","shoot_down")
	var is_moving := move_input != Vector2.ZERO
	
	#CharacterBody2D 通过 velocity 配合 move_and_silde() 完成移动
	velocity = move_input * _get_effective_move_speed()  #velocity是CharacterBody2D的成员变量
	move_and_slide()
	_set_move_sfx_active(is_moving)
	
	if current_shot_pattern == PickupConfig.ShotPattern.SPIRAL:
		_try_auto_spiral_shoot()
	elif shoot_input != Vector2.ZERO:#按键抬起不恢复默认方向
		_try_shoot(shoot_input)
		
	_update_facing(move_input, shoot_input) #更新角色朝向
	_update_animation() #更新动画
	_update_armed_effect() #更新浮游炮动画
	

#根据当前朝向拼出动画名
func _update_animation() -> void:
	var animation_name := StringName("%s_%s"%[_get_animation_prefix(),facing_suffix])
	
	if not body_sprite.sprite_frames.has_animation(animation_name):
		var fallback_animation_name := StringName("%s_%s"%[NORMAL_ANIMATION_PREFIX,facing_suffix])
		if not body_sprite.sprite_frames.has_animation(fallback_animation_name):
			push_warning("Missing player animation: %s" % animation_name)
			return
		animation_name = fallback_animation_name
		
	if body_sprite.animation != animation_name:
		body_sprite.play(animation_name)


# 射击方向优先于移动方向，用于决定当前显示的角色朝向
# 自动螺旋弹幕期间不再读取射击输入，而是仅按照移动方向更新 armed 动画朝向
func _update_facing(move_input: Vector2, shoot_input: Vector2) -> void:
	if current_shot_pattern == PickupConfig.ShotPattern.SPIRAL:
		if move_input != Vector2.ZERO:
			facing_suffix = _vector_to_facing_suffix(move_input)
		return
	
	if shoot_input != Vector2.ZERO:
		facing_suffix = _vector_to_facing_suffix(shoot_input)
	elif move_input != Vector2.ZERO:
		facing_suffix = _vector_to_facing_suffix(move_input)


# 尝试发射子弹：先检查冷却，再根据当前弹幕模式发射
func _try_shoot(shoot_input: Vector2) -> void:
	if not shooting_timer.is_stopped():
		return

	var shoot_direction := shoot_input.normalized()
	var has_spawned_bullet := _fire_bullets(shoot_direction)
	if has_spawned_bullet: #判断射了没
		_play_sfx(shoot_sfx_player)
	shooting_timer.start(_get_effective_fire_interval())

# 道具统一通过该接口影响玩家，pickup场景不直接改变player内部细节
func apply_pickup(config: PickupConfig) -> bool:
	if config == null :
		return false
	var applied := false
	var should_refresh_shooting_timer := false
	var buff_duration := maxf(config.duration,0.0)
	var has_form_override :=(
		config.player_form_mode != PickupConfig.PlayerFormMode.NORMAL
		or config.shot_pattern != PickupConfig.ShotPattern.NORMAL
	)
	var has_fire_rate_override := not is_equal_approx(
		config.fire_rate_multiplier,
		DEFAULT_FIRE_RATE_MULTIPLTER
	)
	if not is_equal_approx(config.move_speed_multiplier,DEFAULT_MOVE_SPEED_MULTIPLIER):
		current_move_speed_multiplier = config.move_speed_multiplier
		speed_buff_time_left = buff_duration
		applied = true
	
	# 普通射速道具与形态专属射速分开维护，避免覆盖（其他->螺旋）
	if has_fire_rate_override and not has_form_override:
		rapid_fire_rate_multiplier = config.fire_rate_multiplier
		rapid_buff_time_left = buff_duration
		should_refresh_shooting_timer = true
		applied = true
		
	if has_form_override:
		current_form_mode = config.player_form_mode
		current_shot_pattern = config.shot_pattern
		form_fire_rate_multiplier =(
			config.fire_rate_multiplier if has_fire_rate_override else DEFAULT_FIRE_RATE_MULTIPLTER
		)
		form_buff_time_left = buff_duration
		spiral_phase = 0.0 
		should_refresh_shooting_timer = true
		applied = true
		
	if should_refresh_shooting_timer:
		_refresh_shooting_timer_wait_time()
	if applied:
		_play_sfx(pickup_sfx_player)
		
	return applied
	
	
# 伤害统一管理接口
func apply_damage(amount: int) -> bool:
	if is_dead:
		return false
	if amount <= 0:
		return false
	if invincibility_time_left > 0.0:
		return false
		
	current_health = maxi(current_health - amount, 0 )
	if current_health <= 0:
		_die()
		return true
		
	_start_invincibility()
	return true
		
# 获取玩家当前生命值
func get_current_health() -> int:
		return current_health
		
# 根据当前弹幕模式发射子弹，并返回这次是否至少成功生成了一枚子弹
func _fire_bullets(base_direction: Vector2) -> bool:
	if current_shot_pattern == PickupConfig.ShotPattern.SPIRAL:
		var has_spawned_forward_bullet := _spawn_bullet(base_direction)
		var has_spawned_backward_bullet := _spawn_bullet(base_direction.rotated(PI))
		spiral_phase = wrapf(spiral_phase + SPIRAL_PHASE_STEP,0.0,TAU)
		return has_spawned_backward_bullet or has_spawned_forward_bullet
		
	return _spawn_bullet(base_direction)


#实例化并生成一枚子弹
func _spawn_bullet(shoot_direction: Vector2) -> bool:
	if not _can_spawn_bullet(shoot_direction):
		return false
	
	var bullet := BULLET_SCENCE.instantiate() as Bullet
	if bullet == null:
		return false
		
	bullet.top_level = true
	bullet.setup(shoot_direction)
	
	# 子弹被挂载到主场景下，避免跟随玩家一起移动
	var spawn_parent := get_tree().current_scene
	if spawn_parent == null:
		return false
		
	spawn_parent.add_child(bullet)
	bullet.global_position = global_position + shoot_direction * bullet_spawn_distance
	return true


# 发生前检查从玩家中心到子弹出生点是否有世界碰撞阻挡
func _can_spawn_bullet(shoot_direction) -> bool:
	var spawn_position :Vector2= global_position + shoot_direction * bullet_spawn_distance
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return true
	
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		spawn_position,
		WORLD_COLLSION_MASK
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	
	var hit_result: Dictionary = space_state.intersect_ray(query)
	return hit_result.is_empty()
# 螺旋形态固定节奏向360度发射子弹
func _try_auto_spiral_shoot() -> void:
	if not shooting_timer.is_stopped():
		return
	
	
	var spiral_dirction := Vector2.RIGHT.rotated(spiral_phase)
	var has_spawned_bullet := _fire_bullets(spiral_dirction)
	if has_spawned_bullet:
		_play_sfx(shoot_sfx_player)
	shooting_timer.start(_get_effective_fire_interval())

# 每帧更新道具buff剩余时间，并在到期后恢复默认状态
func _update_pickup_effects(delta:float) -> void:
	if speed_buff_time_left >0.0:
		speed_buff_time_left = maxf(speed_buff_time_left -delta,0.0)
		if speed_buff_time_left <= 0.0:
			current_move_speed_multiplier = DEFAULT_MOVE_SPEED_MULTIPLIER
	if rapid_buff_time_left >0.0:
			rapid_buff_time_left = maxf(rapid_buff_time_left-delta,0.0)
			if rapid_buff_time_left <= 0.0:
				rapid_fire_rate_multiplier = DEFAULT_FIRE_RATE_MULTIPLTER
				_refresh_shooting_timer_wait_time()
	if form_buff_time_left >0.0:
			form_buff_time_left = maxf(form_buff_time_left-delta,0.0)
			if form_buff_time_left <= 0.0:
				current_form_mode = PickupConfig.PlayerFormMode.NORMAL
				current_shot_pattern = PickupConfig.ShotPattern.NORMAL
				form_fire_rate_multiplier = DEFAULT_FIRE_RATE_MULTIPLTER
				spiral_phase = 0.0
				_refresh_shooting_timer_wait_time()
	
	
# 更新玩家无敌时间，并管理闪烁效果
func _update_invincibility(delta: float) -> void:
	if invincibility_time_left <= 0.0:
		return
		
	invincibility_time_left = maxf(invincibility_time_left - delta, 0.0 )
	if invincibility_time_left > 0.0:
		return
		
	_set_hurt_blink_enabled(false)
	
	
func _get_effective_move_speed() -> float:
	return move_speed * current_move_speed_multiplier


# 计算有效的开火时间隔，射速倍率越高，开火间隔越短
func _get_effective_fire_interval() -> float:
	return maxf(fire_interval/_get_effective_fire_multiplier(),0.01)


#强化状态激活时优先使用形态自带的射速倍率，否则退回普通射速倍率
func _get_effective_fire_multiplier() -> float:
	if _has_active_form_override():
		return maxf(form_fire_rate_multiplier,0.01)
		
	return maxf(rapid_fire_rate_multiplier,0.01)
	
	
# 只要玩家仍处于特殊弹幕状态，就视为强化仍在生效
func _has_active_form_override() -> bool:
	return(
		current_form_mode != PickupConfig.PlayerFormMode.NORMAL
		or current_shot_pattern != PickupConfig.ShotPattern.NORMAL
	)
	
	
#统一射击计时器的基础间隔，避免buff生效使用旧数值
func _refresh_shooting_timer_wait_time() ->void:
	var new_interval := _get_effective_fire_interval()
	shooting_timer.wait_time = new_interval
	
	#如果玩家在冷却时拾取了射速更快的buff,需立即缩短
	if shooting_timer.is_stopped():
		return
	if shooting_timer.time_left <= new_interval:
		return
	
	shooting_timer.start(new_interval)
	
	
# 开启玩家受伤后的无敌
func _start_invincibility() -> void:
	invincibility_time_left = maxf(invincibility_duration,0.0)
	_set_hurt_blink_enabled(invincibility_time_left > 0.0)
	
	
# 受击闪烁开关，便于与其他条件解耦
func _set_hurt_blink_enabled(enabled: bool) -> void:
	var sprite_material := body_sprite.material as ShaderMaterial 
	if sprite_material != null:
		sprite_material.set_shader_parameter(BLINK_ENABLE_SHADER_PAREMETER,enabled)


# 玩家生命值归零，进入死亡状态
func _die()->void:
	is_dead = true
	velocity = Vector2.ZERO
	invincibility_time_left = 0.0
	_set_hurt_blink_enabled(false)
	shooting_timer.stop()
	_set_move_sfx_active(false)
	armed_effect_sprite.visible = false
	armed_effect_sprite.stop()
	


# 根据状态选择动画前缀
func _get_animation_prefix() -> StringName:
	if current_form_mode == PickupConfig.PlayerFormMode.ARMED:
		return ARMED_ANIMATION_PREFIX
	
	return NORMAL_ANIMATION_PREFIX


# 强化状态下显示浮游炮的动画，结束时隐藏并结束播放
func _update_armed_effect() -> void:
	var is_armed := current_form_mode ==PickupConfig.PlayerFormMode.ARMED
	
	if not is_armed:
		if armed_effect_sprite.visible:
			armed_effect_sprite.visible = false
		if armed_effect_sprite.is_playing():
			armed_effect_sprite.stop()
		return
	if not armed_effect_sprite.visible:
		armed_effect_sprite.visible = true
	if armed_effect_sprite.is_playing():
		return
	if armed_effect_sprite.sprite_frames == null:
		return
	
	if armed_effect_sprite.sprite_frames.has_animation(&"default"):#先检查默认
		armed_effect_sprite.play(&"default")
		_play_sfx(s_pickup_sfx_player)


# 主场景在结算时可调用该接口，统一关闭玩家仍在播放的音频
func stop_runtime_audio() ->void:
	_set_move_sfx_active(false)
	if shoot_sfx_player != null and shoot_sfx_player.playing:
		shoot_sfx_player.stop()
	if pickup_sfx_player != null and pickup_sfx_player.playing:
		pickup_sfx_player.stop()
	
	
# 根据移动状态开关音效
func _set_move_sfx_active(active: bool) -> void:
	if move_sfx_player == null and move_sfx_player.stream == null:
		return
	
	if active:
		if not move_sfx_player.playing:
			move_sfx_player.play()
		return
		
	if move_sfx_player.playing:
		move_sfx_player.stop()
		

# 一次性音效通源石油“暂停后重播”，保证从头触发
func _play_sfx(audio_player: AudioStreamPlayer) ->void:
	if audio_player == null or audio_player.stream == null:
		return
	
	audio_player.stop()
	audio_player.play()

#将任意二维向量映射为四向动画
#对角输入优先取大值，避免歧义（灵活设备有效）
func _vector_to_facing_suffix(direction: Vector2)->StringName:
	if abs(direction.x) >= abs(direction.y):
		return &"right" if direction.x > 0.0 else &"left"
		
	return &"down" if direction.y > 0.0 else &"up" 
	
func test() -> void:
	current_form_mode = PickupConfig.PlayerFormMode.ARMED
	current_shot_pattern = PickupConfig.ShotPattern.SPIRAL
	form_fire_rate_multiplier = 20.0
	spiral_phase = 0.8
