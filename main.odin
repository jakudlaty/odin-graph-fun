package flow

import time "core:time"
import "core:slice"
import "core:math"
import rl "vendor:raylib"

Particle :: struct {
  pos : rl.Vector2,
  vel : rl.Vector2,
  connections: [dynamic]int,
}

lines_intersect :: proc(p1, p2, p3, p4: rl.Vector2) -> bool {
  ccw :: proc(a, b, c: rl.Vector2) -> bool {
    return (c.y - a.y) * (b.x - a.x) > (b.y - a.y) * (c.x - a.x)
  }
  return ccw(p1, p3, p4) != ccw(p2, p3, p4) && ccw(p1, p2, p3) != ccw(p1, p2, p4)
}

add_particle :: proc(particles: ^[dynamic]Particle, pos: rl.Vector2) {
  new_idx := len(particles)
  new_p := Particle{pos, {0,0}, make([dynamic]int)}
  
  if len(particles) > 0 {
    Neighbor :: struct {
      idx: int,
      dist: f32,
    }
    neighbors := make([dynamic]Neighbor, 0, len(particles))
    defer delete(neighbors)
    
    for p, i in particles {
      real_dist := rl.Vector2Distance(pos, p.pos)
      effective_dist := real_dist
      
      // Check if connection (pos, p.pos) intersects any existing edge
      intersect := false
      for other_p, j in particles {
        for conn_idx in other_p.connections {
          if conn_idx < j do continue // Draw each line only once
          
          p1 := other_p.pos
          p2 := particles[conn_idx].pos
          
          // Avoid checking against edges connected to the potential neighbor
          if j == i || conn_idx == i do continue
          
          if lines_intersect(pos, p.pos, p1, p2) {
            intersect = true
            break
          }
        }
        if intersect do break
      }
      
      if intersect {
        effective_dist *= 2.0
      }
      
      append(&neighbors, Neighbor{i, effective_dist})
    }
    
    slice.sort_by(neighbors[:], proc(a, b: Neighbor) -> bool {
      return a.dist < b.dist
    })
    
    count := math.min(3, len(neighbors))
    for i in 0..<count {
      neighbor_idx := neighbors[i].idx
      append(&new_p.connections, neighbor_idx)
      append(&particles[neighbor_idx].connections, new_idx)
    }
  }
  append(particles, new_p)
}

remove_connection :: proc(particles: ^[dynamic]Particle, mouse_p: rl.Vector2) {
  min_dist: f32 = 10.0
  p_idx := -1
  q_idx := -1
  conn_local_idx := -1

  for &p, i in particles {
    for neighbor_idx, j in p.connections {
      if neighbor_idx < i do continue
      q := particles[neighbor_idx]

      pa := mouse_p - p.pos
      ba := q.pos - p.pos
      denom := rl.Vector2DotProduct(ba, ba)
      if denom == 0 do continue
      
      t := math.clamp(rl.Vector2DotProduct(pa, ba) / denom, 0, 1)
      closest := p.pos + ba * f32(t)
      dist := rl.Vector2Distance(mouse_p, closest)

      if dist < min_dist {
        min_dist = dist
        p_idx = i
        q_idx = neighbor_idx
        conn_local_idx = j
      }
    }
  }

  if p_idx != -1 {
    if len(particles[p_idx].connections) > 1 && len(particles[q_idx].connections) > 1 {
      unordered_remove(&particles[p_idx].connections, conn_local_idx)
      for conn, k in particles[q_idx].connections {
        if conn == p_idx {
          unordered_remove(&particles[q_idx].connections, k)
          break
        }
      }
    }
  }
}

AppState :: struct {
  window_width:  i32,
  window_height: i32,
  target_dist:   f32,
  slider_rect:   rl.Rectangle,
}

update_physics :: proc(particles: ^[dynamic]Particle, state: AppState) {
  // 1. Global repulsion & Jitter
  for i in 0..<len(particles) {
    for j in i+1..<len(particles) {
      p := &particles[i]
      q := &particles[j]
      
      diff := q.pos - p.pos
      dist := rl.Vector2Length(diff)
      
      if dist < 10 {
        p.vel += {f32(rl.GetRandomValue(-5, 5)) * 0.1, f32(rl.GetRandomValue(-5, 5)) * 0.1}
        q.vel -= {f32(rl.GetRandomValue(-5, 5)) * 0.1, f32(rl.GetRandomValue(-5, 5)) * 0.1}
      }

      if dist == 0 || dist >= state.target_dist do continue

      dir := diff / dist
      force_mag := (dist - state.target_dist) * 0.0005
      
      p.vel += dir * force_mag
      q.vel -= dir * force_mag
    }
  }

  // 2. Attraction
  for &p in particles {
    for conn_idx in p.connections {
      q := particles[conn_idx]
      diff := q.pos - p.pos
      dist := rl.Vector2Length(diff)
      if dist <= state.target_dist do continue
      
      p.vel += (diff / dist) * (dist - state.target_dist) * 0.0005
    }
  }

  // 3. Boundaries & Integration
  width  := f32(state.window_width)
  height := f32(state.window_height)
  center := rl.Vector2{width * 0.5, height * 0.5}

  for &p in particles {
    if p.pos.x < 0 || p.pos.x > width || p.pos.y < 0 || p.pos.y > height {
      p.vel += rl.Vector2Normalize(center - p.pos) * 0.5
    }
    p.vel *= 0.99
    p.pos += p.vel
  }
}

draw_scene :: proc(particles: [dynamic]Particle, state: AppState) {
  rl.BeginDrawing()
  rl.ClearBackground(rl.RAYWHITE)
  
  // Connections
  for p, i in particles {
    for conn_idx in p.connections {
      if conn_idx < i do continue
      
      q := particles[conn_idx]
      dist := rl.Vector2Distance(p.pos, q.pos)
      tension := math.clamp(math.abs(dist - state.target_dist) / state.target_dist, 0, 1)
      
      color := rl.Color{
        u8(200 + 55 * tension),
        u8(200 * (1.0 - tension)),
        u8(200 * (1.0 - tension)),
        255,
      }
      rl.DrawLineV(p.pos, q.pos, color)
    }
  }

  // Nodes
  for p in particles {
    rl.DrawCircleV(p.pos, 5, rl.DARKBLUE)
  }

  // UI Slider
  rl.DrawRectangleRec(state.slider_rect, rl.LIGHTGRAY)
  handle_x := state.slider_rect.x + (state.target_dist - 50.0) / (500.0 - 50.0) * state.slider_rect.width
  rl.DrawRectangleRec({handle_x - 5, state.slider_rect.y - 5, 10, 30}, rl.DARKGRAY)
  rl.DrawText(rl.TextFormat("Distance: %.0f", state.target_dist), i32(state.slider_rect.x + state.slider_rect.width + 10), 20, 20, rl.BLACK)

  // Controls Overlay
  controls_y : i32 = 60
  rl.DrawText("LMB: Add Point", 20, controls_y, 20, rl.GRAY)
  rl.DrawText("RMB: Remove Connection", 20, controls_y + 25, 20, rl.GRAY)
  rl.DrawText("R / C: Reset All", 20, controls_y + 50, 20, rl.GRAY)

  rl.EndDrawing()
}

main :: proc() {
  particles : [dynamic]Particle
  state := AppState{
    window_width = 1920,
    window_height = 1080,
    target_dist = 100.0,
    slider_rect = {20, 20, 300, 20},
  }
  slider_dragging := false

  rl.SetConfigFlags({.WINDOW_RESIZABLE})
  rl.InitWindow(state.window_width, state.window_height, "graph-fun")
  rl.SetTargetFPS(60)
  
  for !rl.WindowShouldClose() {
    state.window_width = rl.GetScreenWidth()
    state.window_height = rl.GetScreenHeight()
    mouse_p := rl.GetMousePosition()

    // Slider Logic
    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse_p, state.slider_rect) {
      slider_dragging = true
    }
    if !rl.IsMouseButtonDown(.LEFT) {
      slider_dragging = false
    }
    if slider_dragging {
      state.target_dist = math.clamp(50.0 + (mouse_p.x - state.slider_rect.x) / state.slider_rect.width * 450.0, 50.0, 500.0)
    }

    // Input Logic
    if rl.IsMouseButtonPressed(.LEFT) && !rl.CheckCollisionPointRec(mouse_p, state.slider_rect) {
      add_particle(&particles, mouse_p)
    }
    if rl.IsMouseButtonPressed(.RIGHT) {
      remove_connection(&particles, mouse_p)
    }

    if rl.IsKeyPressed(.R) || rl.IsKeyPressed(.C) {
      for &p in particles {
        delete(p.connections)
      }
      clear(&particles)
    }

    update_physics(&particles, state)
    draw_scene(particles, state)
  }
}
