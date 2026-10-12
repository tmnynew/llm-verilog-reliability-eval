设计一个看门狗定时器 `watchdog`：使能后若连续 TIMEOUT 个时钟周期没有收到 kick 喂狗信号，则 timeout 置 1 并保持，直到 kick、关闭使能或复位。
