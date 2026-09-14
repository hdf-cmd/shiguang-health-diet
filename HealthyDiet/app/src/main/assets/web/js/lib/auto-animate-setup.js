/* AutoAnimate 只提供 ESM 构建：用 module 脚本桥接到 window 供 app.js 使用 */
import { autoAnimate } from './auto-animate.min.js';
window.autoAnimate = autoAnimate;
