# דוח מדידות ביצועים

Commit: `7cd6ff40821eab4f1488d05158912f589fabb541` · מצב: profile · מטמון: cold

הרצה שלמה: true · הצלחה: true

| תרחיש | מצב | n | p50 ms | p95 ms | p99 ms | build p95 ms | raster p95 ms | RSS peak MiB |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| startup.first_content | passed | 4 | 598.698 | 797.443 | 797.443 | 53.598 | 179.940 | 326.512 |
| startup.window_useful | passed | 4 | 261.000 | 406.000 | 406.000 | — | — | — |
| book.short.open | passed | 16 | 100.109 | 108.808 | 108.808 | 25.776 | 4.129 | 913.879 |
| book.short.scroll | passed | 16 | 947.113 | 958.836 | 958.836 | 1.975 | 5.106 | 665.391 |
| book.short.jump_forward | passed | 16 | 65.734 | 77.919 | 77.919 | 37.034 | 2.645 | 540.723 |
| book.short.jump_backward | passed | 16 | 73.626 | 82.611 | 82.611 | 46.071 | 2.583 | 526.477 |
| book.short.warmup_complete | passed | 16 | 0.039 | 0.078 | 0.078 | — | — | 521.539 |
| book.short.steady_scroll | passed | 16 | 934.960 | 951.997 | 951.997 | 1.977 | 2.876 | 521.609 |
| book.short.close | passed | 16 | 361.726 | 368.598 | 368.598 | 3.398 | 2.691 | 531.688 |
| book.medium.open | passed | 16 | 114.932 | 156.180 | 156.180 | 34.474 | 6.593 | 534.730 |
| book.medium.scroll | passed | 16 | 1255.844 | 1373.520 | 1373.520 | 14.647 | 4.773 | 541.207 |
| book.medium.jump_forward | passed | 16 | 80.982 | 733.638 | 733.638 | 70.375 | 2.554 | 667.012 |
| book.medium.jump_backward | passed | 16 | 63.994 | 95.440 | 95.440 | 50.553 | 2.658 | 558.598 |
| book.medium.warmup_complete | passed | 16 | 1103.396 | 1170.712 | 1170.712 | 9.155 | 4.630 | 549.758 |
| book.medium.steady_scroll | passed | 16 | 932.953 | 947.187 | 947.187 | 1.920 | 3.415 | 558.379 |
| book.medium.close | passed | 16 | 359.977 | 368.707 | 368.707 | 3.024 | 2.476 | 550.734 |
| book.long.open | passed | 16 | 358.885 | 453.596 | 453.596 | 115.995 | 7.165 | 646.957 |
| book.long.scroll | passed | 16 | 952.783 | 1315.564 | 1315.564 | 2.193 | 6.767 | 982.871 |
| book.long.jump_forward | passed | 16 | 127.964 | 770.348 | 770.348 | 415.375 | 2.777 | 1136.324 |
| book.long.jump_backward | passed | 16 | 117.608 | 712.763 | 712.763 | 452.023 | 2.595 | 1014.855 |
| book.long.warmup_complete | passed | 16 | 30863.669 | 35484.112 | 35484.112 | 8.761 | 2.628 | 942.855 |
| book.long.steady_scroll | passed | 16 | 932.593 | 979.723 | 979.723 | 1.870 | 7.337 | 984.188 |
| book.long.close | passed | 16 | 363.371 | 368.282 | 368.282 | 4.361 | 3.142 | 917.141 |
| windows.native_open_close | skipped | 0 | — | — | — | — | — | — |
| queues.depth | skipped | 0 | — | — | — | — | — | — |

| תרחיש | CPU ממוצע % ליבה | כיסוי CPU % | private peak MiB | heap אחרי p50 MiB | handles peak | תהליכים peak |
|---|---:|---:|---:|---:|---:|---:|
| startup.first_content | — | 0.000 | 229.141 | — | 554.000 | 1.000 |
| startup.window_useful | — | 0.000 | 229.141 | — | 554.000 | 1.000 |
| book.short.open | — | 0.000 | 773.215 | 74.956 | 612.000 | 1.000 |
| book.short.scroll | 30.318 | 50.056 | 380.121 | 82.218 | 619.000 | 1.000 |
| book.short.jump_forward | — | 0.000 | 410.695 | 74.079 | 611.000 | 1.000 |
| book.short.jump_backward | — | 0.000 | 367.535 | 74.028 | 608.000 | 1.000 |
| book.short.warmup_complete | — | 0.000 | — | 79.682 | — | — |
| book.short.steady_scroll | 38.443 | 44.211 | 384.367 | 77.180 | 616.000 | 1.000 |
| book.short.close | — | 0.000 | 386.188 | 74.315 | 612.000 | 1.000 |
| book.medium.open | — | 0.000 | 392.242 | 99.170 | 614.000 | 1.000 |
| book.medium.scroll | 161.693 | 65.977 | 404.977 | 89.660 | 613.000 | 1.000 |
| book.medium.jump_forward | — | 0.000 | 459.465 | 86.949 | 606.000 | 1.000 |
| book.medium.jump_backward | — | 0.000 | 415.871 | 84.614 | 606.000 | 1.000 |
| book.medium.warmup_complete | 111.383 | 50.525 | 408.023 | 94.252 | 612.000 | 1.000 |
| book.medium.steady_scroll | 27.193 | 46.886 | 421.410 | 98.255 | 606.000 | 1.000 |
| book.medium.close | — | 0.000 | 414.285 | 88.147 | 605.000 | 1.000 |
| book.long.open | — | 0.000 | 457.117 | 175.001 | 607.000 | 1.000 |
| book.long.scroll | 282.017 | 55.714 | 697.477 | 567.113 | 615.000 | 1.000 |
| book.long.jump_forward | 192.360 | 14.211 | 962.188 | 302.778 | 608.000 | 1.000 |
| book.long.jump_backward | — | 0.000 | 734.641 | 301.517 | 604.000 | 1.000 |
| book.long.warmup_complete | 131.014 | 98.291 | 787.727 | 462.668 | 611.000 | 1.000 |
| book.long.steady_scroll | 84.085 | 46.506 | 859.918 | 468.270 | 611.000 | 1.000 |
| book.long.close | — | 0.000 | 777.426 | 464.626 | 613.000 | 1.000 |
| windows.native_open_close | — | — | — | — | — | — |
| queues.depth | — | — | — | — | — | — |

אחוזונים: nearest-rank על דגימות מוצלחות בלבד, ללא warmup. מקף מציין מדד חסר. CPU: ‏100% = ליבה אחת; private memory הוא commit פרטי, ואינו אומדן לזיכרון native בלבד. דגימות גודל וזמן כיסוי CPU מפורטים ב-JSON.

## מגבלות המדידה

- p95/p99 עם מעט חזרות מתארים את המדגם בלבד; יש לבדוק את n
