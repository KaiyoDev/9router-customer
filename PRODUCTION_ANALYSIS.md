# 9Router Production Optimization — ARM64 TV Box (~2GB RAM)

## 1. Phân tích Source Code

### Framework & Runtime
| Thuộc tính | Giá trị |
|---|---|
| Framework | Next.js 16.1.6 (webpack, **không** phải Turbopack) |
| Output mode | `standalone` (`.next/standalone/`) |
| Package manager | npm (lockfile `package-lock.json` bị ignore — dùng `npm install`) |
| Ngôn ngữ | Plain JS (ESM), không TypeScript |
| Port mặc định | 20128 |

### Node.js Version
- **Không có `.nvmrc`** — project không ràng buộc version cứng.
- Tuy nhiên `node:sqlite` (built-in driver fallback) yêu cầu **Node ≥ 22.5**.
- **Khuyến nghị**: Node.js 22 LTS (ARM64) — tận dụng được native sqlite, tránh sql.js WASM overhead.

### Database / Storage
- **SQLite** với fallback chain: `better-sqlite3` (native, optional) → `node:sqlite` (Node ≥22.5) → `sql.js` (WASM fallback).
- Trên ARM64 TV Box không có build-tools (`python3`, `make`, `g++`), `better-sqlite3` sẽ fail → fallback sang `node:sqlite` (tốt nhất) hoặc `sql.js`.
- **DATA_DIR**: `/var/lib/9router` (hoặc env `DATA_DIR`), chứa `db/data.sqlite`.
- **Usage/Log files**: `~/.9router/usage.json` + `log.txt` — **không** theo `DATA_DIR`.

### Memory Hogs (nặng nhất)
1. **Next.js standalone runtime**: ~150–250 MB RAM khởi động (bao gồm webpack runtime + tất cả API routes).
2. **Provider registry**: ~40+ provider definitions được load lúc khởi động vào memory.
3. **Translator engine**: Tất cả translator modules (`open-sse/translator/*`) được require/import eager.
4. **Background token refresh**: Interval 5 phút, mỗi tick đọc DB + thực hiện HTTP gọi OAuth refresh.
5. **In-memory usage ring buffer**: `RING_CAP = 50` entries + global state cho pending requests/stats.
6. **sql.js WASM**: Nếu `better-sqlite3` không build được, sql.js load WASM ~2–5 MB.

### Background Jobs
| Job | Tần suất | Tác động RAM |
|---|---|---|
| `startBackgroundTokenRefresh` | Mỗi 5 phút | Nhẹ — read DB + OAuth HTTP |
| `statsEmitter` (pending requests) | Debounce 150ms | Rất nhẹ |
| `connectionMapCache` TTL 30s | Khi cần | Rất nhẹ |

### Logging
- Default: console.log chỉ trong dev.
- Production: `ENABLE_REQUEST_LOGS=false` (mặc định) — không ghi request body.
- Usage log: `~/.9router/log.txt` — **có thể phát triển vô hạn**, cần rotation.
- Không có Winston/Pino — chỉ dùng `console.*`.

### Dependencies nặng
- `next` (16.x) — lõi Next.js
- `react` + `react-dom` (19.x)
- `recharts` — biểu đồ usage (chỉ dùng ở dashboard frontend)
- `monaco-editor` — code editor trong dashboard (client-side only)
- `sql.js` — SQLite pure JS (fallback, ~2MB WASM)
- `undici` — HTTP client
- `jose` — JWT
- `bcryptjs` — password hashing

### Không có
- ❌ Chromium / Puppeteer / Playwright
- ❌ Redis / external database
- ❌ GraphQL
- ❌ TypeScript compiler trong runtime

---

## 2. Đề xuất thay đổi trước khi sửa

### Ưu tiên cao (ảnh hưởng RAM trực tiếp)
1. **Set `NODE_OPTIONS`** với `--max-old-space-size=512` — giới hạn V8 heap ~512MB, tránh OOM trên server 2GB.
2. **Set `ENABLE_REQUEST_LOGS=false`** —杜绝 viết request body xuống disk.
3. **Set `OBSERVABILITY_ENABLED=false`** nếu không dùng cloud sync — giảm background traffic.
4. **Xoá `tests/` và `cli/` khỏi container** — không cần runtime.
5. **Dùng Node.js 22 LTS ARM64** — có `node:sqlite` built-in, bỏ `sql.js` WASM overhead.
6. **Log rotation** cho `~/.9router/log.txt` — dùng logrotate hoặc `rotating-file-stream`.

### Ưu tiên trung bình
7. **Disable unused providers** trong config để giảm registry size.
8. **Tăng `BACKGROUND_REFRESH_LEAD_MS`** hoặc disable hoàn toàn nếu không dùng OAuth.
9. **Giảm `RING_CAP`** từ 50 xuống 20 trong `usageRepo.js` (tối ưu RAM).
10. **Tắt `serverComponentsHmrCache`** trong production (tiện ích chỉ cho dev).

### Nhược / Không khuyến nghị
11. ~~Chuyển sang Turbopack~~ — Next.js 16 chưa ổn định, webpack đã đủ.
12. ~~Thay thế sql.js bằng better-sqlite3~~ — cần build-native, phức tạp trên ARM64 low-end.
13. ~~Thêm Redis~~ — vi phạm ràng buộc "không thêm service mới".

---

## 3. Dự kiến Memory Footprint

### Idle (không có request)
| Thành phần | Dự kiến |
|---|---|
| Node.js runtime base | ~60 MB |
| Next.js standalone server | ~80–120 MB |
| Provider registry + translators | ~30–50 MB |
| SQLite (sql.js WASM hoặc node:sqlite) | ~5–10 MB |
| Background token refresh scheduler | ~2 MB |
| **Tổng idle ước tính** | **~150–220 MB RSS** |

### Khi xử lý request (1 concurrent stream)
| Thành phần | Tăng thêm |
|---|---|
| Request body buffer | ~1–5 MB (tuỳ payload) |
| Response stream buffer | ~1–3 MB |
| SSE connection | ~0.5 MB |
| **Tổng peak ước tính** | **~200–300 MB RSS** |

### Giới hạn an toàn
- `NODE_OPTIONS="--max-old-space-size=512"` → V8 heap ceiling 512 MB.
- Với 1.4 GB RAM available, còn ~1.1 GB cho OS + container overhead → **an toàn**.

---

## 4. Build Output Standalone

Next.js `output: "standalone"` tạo thư mục `.next/standalone/` chứa:
- `server.js` — Next standalone server
- `.next/static/` — static assets
- `node_modules/` — chỉ những deps thực sự cần (trimmed)
- `custom-server.js` — wrapper IP sanitization

**Lưu ý**: `serverExternalPackages` trong `next.config.mjs` liệt kê `better-sqlite3`, `sql.js`, `node:sqlite`, `bun:sqlite`, `open` — các package này **không được copy vào standalone**, phải được cung cấp riêng hoặc để npm install đầy đủ.

Trong Containerfile, ta sẽ `COPY node_modules/` từ builder stage để đảm bảo tất cả deps có sẵn.
