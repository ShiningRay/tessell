# 几何与约束全部用 struct：栈分配、按值传递。
# 布局与绘制热路径的零堆分配指标依赖这一层。

module Quartz
  struct Point
    getter x : Float32
    getter y : Float32

    def initialize(@x : Float32 = 0.0_f32, @y : Float32 = 0.0_f32)
    end

    def +(other : Point) : Point
      Point.new(@x + other.x, @y + other.y)
    end
  end

  struct Size
    getter width : Float32
    getter height : Float32

    def initialize(@width : Float32 = 0.0_f32, @height : Float32 = 0.0_f32)
    end

    def zero? : Bool
      @width <= 0.0_f32 && @height <= 0.0_f32
    end
  end

  struct Rect
    getter origin : Point
    getter size : Size

    def initialize(@origin : Point = Point.new, @size : Size = Size.new)
    end

    def self.new(x : Float32, y : Float32, w : Float32, h : Float32)
      new(Point.new(x, y), Size.new(w, h))
    end

    def max_x : Float32
      @origin.x + @size.width
    end

    def max_y : Float32
      @origin.y + @size.height
    end

    def contains?(p : Point) : Bool
      p.x >= @origin.x && p.x <= max_x && p.y >= @origin.y && p.y <= max_y
    end

    # 脏矩形合并：返回覆盖两者的最小矩形。
    def union(other : Rect) : Rect
      x0 = Math.min(@origin.x, other.origin.x)
      y0 = Math.min(@origin.y, other.origin.y)
      x1 = Math.max(max_x, other.max_x)
      y1 = Math.max(max_y, other.max_y)
      Rect.new(x0, y0, x1 - x0, y1 - y0)
    end
  end

  struct Insets
    getter top : Float32
    getter right : Float32
    getter bottom : Float32
    getter left : Float32

    def initialize(@top : Float32 = 0.0_f32, @right : Float32 = 0.0_f32,
                   @bottom : Float32 = 0.0_f32, @left : Float32 = 0.0_f32)
    end

    def self.all(v : Float32)
      new(v, v, v, v)
    end

    def horizontal : Float32
      @left + @right
    end

    def vertical : Float32
      @top + @bottom
    end
  end

  struct Color
    getter r : Float32
    getter g : Float32
    getter b : Float32
    getter a : Float32

    def initialize(@r : Float32, @g : Float32, @b : Float32, @a : Float32 = 1.0_f32)
    end
  end

  # 一维尺寸约束：自动、固定、比例。用 union 让非法状态不可表示。
  alias Dimension = Auto | Fixed | Fraction

  struct Auto
  end

  struct Fixed
    getter value : Float32

    def initialize(@value : Float32)
    end
  end

  struct Fraction
    getter weight : Float32

    def initialize(@weight : Float32 = 1.0_f32)
    end
  end

  # 布局输入：两遍布局的约束下行阶段使用。
  struct Constraints
    getter min_width : Float32
    getter max_width : Float32
    getter min_height : Float32
    getter max_height : Float32

    def initialize(@min_width : Float32 = 0.0_f32,
                   @max_width : Float32 = Float32::INFINITY,
                   @min_height : Float32 = 0.0_f32,
                   @max_height : Float32 = Float32::INFINITY)
    end

    def self.tight(size : Size)
      new(size.width, size.width, size.height, size.height)
    end

    def loosen : Constraints
      Constraints.new(0.0_f32, @max_width, 0.0_f32, @max_height)
    end

    def constrain(size : Size) : Size
      Size.new(
        size.width.clamp(@min_width, @max_width),
        size.height.clamp(@min_height, @max_height)
      )
    end
  end
end
