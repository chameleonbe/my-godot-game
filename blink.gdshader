shader_type canvas_item;

uniform bool blink_enabled = false;//是否闪烁
uniform float blink_speed : hint_range(1.0, 30.0) = 12.0;//闪烁速度
uniform float hidden_ratio : hint_range(0.0, 1.0) = 0.5;//隐藏时间占比

void fragment(){// 对图片每个像素都执行
	vec4 color = texture(TEXTURE, UV) * COLOR;//像素颜色
	
	if(blink_enabled && color.a >0.0){//color.a  不透明度
		float blink_phase = fract(TIME * blink_speed);//fract() 截取小数部分  
		if(blink_phase < hidden_ratio){
			color.a = 0.0; 
		}
	}
	COLOR = color;
}
