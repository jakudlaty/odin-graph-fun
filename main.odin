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

main :: proc() {
  particles : [dynamic]Particle
  target_dist : f32 = 100.0
  slider_dragging := false

  rl.InitWindow(1920, 1080, "Kaszanka")
  rl.SetTargetFPS(60)
  for !rl.WindowShouldClose() {

    // UI: Slider for target distance
    slider_rect := rl.Rectangle{20, 20, 300, 20}
    mouse_p := rl.GetMousePosition()
    
    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse_p, slider_rect) {
      slider_dragging = true
    }
    if !rl.IsMouseButtonDown(.LEFT) {
      slider_dragging = false
    }
    
    if slider_dragging {
      target_dist = 50.0 + (mouse_p.x - slider_rect.x) / slider_rect.width * (500.0 - 50.0)
      target_dist = math.clamp(target_dist, 50.0, 500.0)
    }

    if rl.IsMouseButtonPressed(.LEFT) && !rl.CheckCollisionPointRec(mouse_p, slider_rect) {
      new_idx := len(particles)
      
      new_p := Particle{mouse_p, {0,0}, make([dynamic]int)}
      
      if len(particles) > 0 {
        Neighbor :: struct {
          idx: int,
          dist: f32,
        }
        neighbors := make([dynamic]Neighbor, 0, len(particles))
        defer delete(neighbors)
        
        for p, i in particles {
          append(&neighbors, Neighbor{i, rl.Vector2Distance(mouse_p, p.pos)})
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
      
      append(&particles, new_p)
    }

    if rl.IsMouseButtonPressed(.RIGHT) {
      min_dist: f32 = 10.0 // Selection threshold in pixels
      p_idx_to_remove := -1
      q_idx_to_remove := -1
      conn_local_idx := -1

      for &p, i in particles {
        for q_idx, j in p.connections {
          if q_idx < i do continue
          q := particles[q_idx]

          // Distance mouse to segment PQ
          pa := mouse_p - p.pos
          ba := q.pos - p.pos
          denom := rl.Vector2DotProduct(ba, ba)
          if denom == 0 do continue
          
          t := math.clamp(rl.Vector2DotProduct(pa, ba) / denom, 0, 1)
          closest := p.pos + ba * f32(t)
          dist := rl.Vector2Distance(mouse_p, closest)

          if dist < min_dist {
            min_dist = dist
            p_idx_to_remove = i
            q_idx_to_remove = q_idx
            conn_local_idx = j
          }
        }
      }

      if p_idx_to_remove != -1 {
        // Constraint: both must have > 1 connection
        if len(particles[p_idx_to_remove].connections) > 1 && len(particles[q_idx_to_remove].connections) > 1 {
          unordered_remove(&particles[p_idx_to_remove].connections, conn_local_idx)
          
          for conn, k in particles[q_idx_to_remove].connections {
            if conn == p_idx_to_remove {
              unordered_remove(&particles[q_idx_to_remove].connections, k)
              break
            }
          }
        }
      }
    }

    // Move particles
    // 1. Global repulsion for all pairs if dist < target_dist
    for i in 0..<len(particles) {
      for j in i+1..<len(particles) {
        p := &particles[i]
        q := &particles[j]
        
        diff := q.pos - p.pos
        dist := rl.Vector2Length(diff)
        
        // Anti-overlap jitter
        if dist < 10 {
          p.vel.x += f32(rl.GetRandomValue(-5, 5)) * 0.1
          p.vel.y += f32(rl.GetRandomValue(-5, 5)) * 0.1
          q.vel.x -= f32(rl.GetRandomValue(-5, 5)) * 0.1
          q.vel.y -= f32(rl.GetRandomValue(-5, 5)) * 0.1
        }

        if dist == 0 do continue
        if dist >= target_dist do continue

        dir := diff / dist
        force_mag := (dist - target_dist) * 0.0005
        
        p.vel += dir * force_mag
        q.vel -= dir * force_mag
      }
    }

    // 2. Attraction for connected pairs only if dist > target_dist
    for &p in particles {
      for conn_idx in p.connections {
        q := particles[conn_idx]
        
        diff := q.pos - p.pos
        dist := rl.Vector2Length(diff)
        
        if dist <= target_dist do continue
        
        dir := diff / dist
        force_mag := (dist - target_dist) * 0.0005
        
        p.vel += dir * force_mag
      }
    }

    for &p in particles {
      if p.pos.x < 0 || p.pos.x > 1920 || p.pos.y < 0 || p.pos.y > 1080 {
        center := rl.Vector2{960, 540}
        diff := center - p.pos
        p.vel += rl.Vector2Normalize(diff) * 0.5
      }
      p.vel *= 0.99
      p.pos += p.vel
    }

    rl.BeginDrawing()
    rl.ClearBackground(rl.RAYWHITE)
    
    // Draw Slider
    rl.DrawRectangleRec(slider_rect, rl.LIGHTGRAY)
    handle_x := slider_rect.x + (target_dist - 50.0) / (500.0 - 50.0) * slider_rect.width
    rl.DrawRectangleRec({handle_x - 5, slider_rect.y - 5, 10, 30}, rl.DARKGRAY)
    rl.DrawText(rl.TextFormat("Dystans: %.0f", target_dist), i32(slider_rect.x + slider_rect.width + 10), 20, 20, rl.BLACK)

    // Draw connections
    for p, i in particles {
        for conn_idx in p.connections {
            if conn_idx < i do continue // Avoid drawing lines twice
            
            q := particles[conn_idx]
            dist := rl.Vector2Distance(p.pos, q.pos)
            
            // Tension coloring
            tension := math.abs(dist - target_dist) / target_dist
            tension = math.min(1.0, tension)
            
            color := rl.Color{
                u8(200 + (255 - 200) * tension),
                u8(200 * (1.0 - tension)),
                u8(200 * (1.0 - tension)),
                255,
            }
            
            rl.DrawLineV(p.pos, q.pos, color)
        }
    }

    for p in particles {
      rl.DrawCircleV(p.pos, 5, rl.DARKBLUE)
    }
    rl.EndDrawing()
  }
}
