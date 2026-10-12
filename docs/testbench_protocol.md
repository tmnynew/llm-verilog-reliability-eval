# 测试台输出协议（Testbench Protocol）

平台通过解析仿真 `stdout` 判定功能仿真结果并为错误分类提供证据，因此所有测试台必须遵守以下协议（实现见 `vleval/tools/tbproto.py`）。

## 1. 顶层模块名

`tb_<module>`，例如 `tb_sync_fifo`。被测模块（DUT）以 `dut` 为实例名，端口按名连接。

## 2. 失败行

每个失败的检查打印一行（最多打印 20 行，避免日志过大）：

```
TB_FAIL tag=<tag> case=<id> exp=<value> got=<value>
```

`tag` 是错误分类体系的证据（表 3），取值：

| tag | 含义 | 映射到的错误类别 |
|---|---|---|
| `func` | 功能比对失败（真值表 / 周期级数据） | 无直接映射，与 Lint 证据组合（E3/E5）或按题型归为 E7/E8 |
| `reset` | 复位事务失败：复位期间/复位后输出不符 | E4 |
| `width` | 明确由位宽造成的失败（可选） | E5 |
| `state` | 状态机比对失败（状态遗漏、转移错误） | E7 |
| `timing` | 输出超出规范声明的延迟窗口、脉冲宽度错误 | E7 |
| `proto` / `handshake` | 事务级协议断言失败（FIFO 空满、UART 帧格式、握手） | E8 |
| `crash` | 测试台未正常结束（由平台补充） | — |

## 3. 结束行（必须恰好一行）

```
TB_RESULT PASS n_checks=<N>
TB_RESULT FAIL n_fail=<M> n_checks=<N>
```

然后调用 `$finish`。缺少 `TB_RESULT` 行（崩溃、死循环、超时 60 s）一律记为失败并打 `crash` 标签。

## 4. 可复现性

- 随机激励只使用 `$random(seed)`，`seed` 由宏 `SEED` 传入（默认 1），平台通过 `+define+SEED=` / `-DSEED=` 设置。
- 每个测试台都带看门狗 `initial #T ... $finish`，T 大于正常运行时间。
- 不依赖 SystemVerilog 特性，所有测试台可在 `iverilog -g2005` 与 `verilator --binary --timing --default-language 1364-2005` 下运行（平台以 IEEE 1364-2005 作为 Verilog 子集上限）。

## 5. 推荐的宏

```verilog
`define CHECK(_t, _id, _e, _g) \
    begin \
        n_checks = n_checks + 1; \
        if ((_e) !== (_g)) begin \
            n_fail = n_fail + 1; \
            if (n_fail <= 20) $display("TB_FAIL tag=%s case=%0d exp=%0h got=%0h", _t, _id, _e, _g); \
        end \
    end
```

宏形参使用 `_t/_id/_e/_g` 这类不会出现在格式字符串中的名字（Icarus 会替换字符串内同名标识符）。

## 6. 分层比对策略（论文 2.2 节）

| 层级 | 策略 | 实现要点 |
|---|---|---|
| L1 | 穷举全部输入组合 | `for` 循环遍历输入，行为级参考函数或真值表 |
| L2 | 周期级比对 + 声明的延迟窗口 | 参考模型与 DUT 在同一 `posedge` 更新，`negedge` 比对；窗口为 0～`allowed_latency` 周期，用 `ref` 与 `ref_d` 双路匹配，并核对脉冲/翻转总数 |
| L3 | 事务级记分板 + 协议断言 | 参考队列仅由输入驱动；数据比对打 `func`，协议断言（满/空、帧格式、握手）打 `proto`，脉冲时序打 `timing` |
