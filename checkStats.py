# -*- coding: utf-8 -*-
import requests
from web3 import Web3
import pandas as pd
import json
import time
import threading
import logging
from charset_normalizer import detect
from datetime import datetime, timezone, timedelta
import sys
import codecs
import os

print("程序启动...")

# 强制标准输出为 utf-8 编码（特别适用于 Windows 系统）
if sys.platform.startswith('win'):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except AttributeError:
        sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer)
    print("已设置控制台编码为 UTF-8")

# 配置日志
logging.basicConfig(
    filename='query_errors.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    encoding='utf-8'
)
print("已配置日志系统")

# 计时开始
start_time = time.time()

# Alchemy API 配置
ALCHEMY_API_KEY = "HOTVxYyYc0_QPdw3gw10dsJWJfC_QhVE"
ALCHEMY_API_URL = f"https://gensyn-testnet.explorer.alchemy.com/api?module=account&action=txlistinternal&address={{address}}&apikey={ALCHEMY_API_KEY}"
ALCHEMY_RPC_URL = f"https://gensyn-testnet.g.alchemy.com/v2/{ALCHEMY_API_KEY}"

print("正在连接 Gensyn 测试网...")
w3 = Web3(Web3.HTTPProvider(ALCHEMY_RPC_URL))

if w3.is_connected():
    print("成功连接到 Gensyn 测试网")
else:
    print("无法连接到 Gensyn 测试网。请检查 RPC URL 或网络。")
    input("按回车键退出...")
    sys.exit(1)

# 合约地址和 ABI
contract_address = Web3.to_checksum_address("0xFaD7C5e93f28257429569B854151A1B8DCD404c2")
print(f"合约地址: {contract_address}")

try:
    print("正在加载 ABI 文件...")
    with open("abi.json", "r", encoding="utf-8") as f:
        abi = json.load(f)
    print("成功加载 ABI 文件")
except Exception as e:
    print(f"无法加载 ABI 文件: {e}")
    input("按回车键退出...")
    sys.exit(1)

try:
    contract = w3.eth.contract(address=contract_address, abi=abi)
    print("成功初始化合约")
except Exception as e:
    print(f"初始化合约失败: {e}")
    input("按回车键退出...")
    sys.exit(1)

# 加载 address.xlsx
try:
    print("正在加载 Excel 文件...")
    if os.path.exists("address.xlsx"):
        df = pd.read_excel("address.xlsx", dtype=str)
        print("已加载 address.xlsx 文件")
    else:
        print("错误: 找不到 address.xlsx 文件")
        input("按回车键退出...")
        sys.exit(1)
    # 清理数据
    print("正在清理数据...")
    for col in df.columns:
        df[col] = df[col].astype(str).str.strip()
    # 替换无效值
    df = df.replace({
        'nan': None,
        'None': None,
        '': None,
        'NaN': None,
        'NULL': None
    })
    print(f"成功加载数据文件，共 {len(df)} 条记录")
    
    # 检查必要的列是否存在
    required_columns = ['name', 'peerID', 'address']
    missing_columns = [col for col in required_columns if col not in df.columns]
    if missing_columns:
        print(f"错误: CSV 文件缺少必要的列: {', '.join(missing_columns)}")
        input("按回车键退出...")
        sys.exit(1)
    
    print("CSV 文件格式检查通过")
    
    # 初始化新列（仅对缺失的列进行初始化）
    print("正在初始化数据列...")
    for col in ["TotalRewards", "TotalWins", "TotalVote", "LastTXtime", "Status", "RewardsChange", "WinsChange", "VoteChange"]:
        if col not in df.columns:
            if col in ["TotalRewards", "TotalWins", "TotalVote"]:
                df[col] = pd.Series(dtype='float64')
            else:
                df[col] = pd.Series(dtype='object')
    
    print("数据初始化完成")
    
    # 自动通过 peerID 查询 address 并补全 address 列
    # 原有的peerID查address补全逻辑可删除或注释，避免重复
    
except Exception as e:
    print(f"加载 CSV 文件时出错: {e}")
    input("按回车键退出...")
    sys.exit(1)

def is_empty_peerid(peer_id):
    return pd.isna(peer_id) or str(peer_id).strip().lower() in ["", "none", "nan", "null"]
def is_empty_address(address):
    addr = str(address).strip()
    return pd.isna(address) or addr.lower() in ["", "none", "nan", "null"] or not Web3.is_address(addr)
def complement_address_peerid(df, contract):
    print("正在获取 address 和 peerID ...")
    for idx, row in df.iterrows():
        address = row.get("address", "")
        peer_id = row.get("peerID", "")
        # address = str(address).strip()
        # peer_id = str(peer_id).strip()
        # 1. peerID查address（优化空值判断）
        if peer_id and is_empty_address(address):
            try:
                eoa_list = contract.functions.getEoa([peer_id]).call()
                eoa = eoa_list[0] if eoa_list else None
                if eoa and Web3.is_address(eoa):
                    print(f"PeerID: {peer_id} 查到address: {eoa}")
                    df.at[idx, "address"] = eoa
                else:
                    print(f"PeerID: {peer_id} 未查到address")
                    df.at[idx, "address"] = '未查到'
            except Exception as e:
                print(f"[错误] PeerID {peer_id[:12]}... 查address失败: {e}")
                df.at[idx, "address"] = '未查到'
        # 2. address查peerID（优化空值判断）
        if address and Web3.is_address(address) and is_empty_peerid(peer_id):
            try:
                peerid_lists = contract.functions.getPeerId([address]).call()
                peerid = peerid_lists[0][0] if peerid_lists and peerid_lists[0] else None
                if peerid:
                    print(f"Address: {address} 查到PeerID: {peerid}")
                    df.at[idx, "peerID"] = peerid
                else:
                    print(f"Address: {address} 未查到PeerID")
                    df.at[idx, "peerID"] = '未查到'
            except Exception as e:
                print(f"[错误] Address {address[:10]}... 查PeerID失败: {e}")
                df.at[idx, "peerID"] = '未查到'
    print("完成")

# 数据初始化完成后，立即进行互补
complement_address_peerid(df, contract)
# 保存原始数据以便比较
print("正在保存原始数据...")
df_prev = df.copy()
print("原始数据保存完成")

def parse_beijing_time(time_str): 
    try:
        current_year = datetime.now().year
        temp_str = f"{current_year}-{time_str}"
        temp_dt = datetime.strptime(temp_str, '%Y-%m-%d %H:%M:%S CST')
        if temp_dt.month > datetime.now().month:
            temp_dt = datetime.strptime(f"{current_year - 1}-{time_str}", '%Y-%m-%d %H:%M:%S CST')
        return temp_dt
    except ValueError:
        return None

def check_time_interval(last_tx_time):
    if not last_tx_time or "无记录" in last_tx_time or "无效地址" in last_tx_time:
        return False
    last_tx_datetime = parse_beijing_time(last_tx_time)
    if not last_tx_datetime:
        return False
    current_time = datetime.now(timezone.utc) + timedelta(hours=8)
    time_diff = current_time - last_tx_datetime.replace(tzinfo=timezone.utc)
    return time_diff.total_seconds() / 3600 > 4 # 4小时未交易   

def get_latest_internal_transaction_time(address, lock):
    retry = 0
    while True:
        try:
            if not Web3.is_address(address):
                return "无效地址"
            url = ALCHEMY_API_URL.format(address=address)
            response = requests.get(url, timeout=5)
            response.encoding = 'utf-8'
            response.raise_for_status()
            data = response.json()
            if data.get("status") == "1" and data.get("result") is not None:
                transactions = data["result"]
                if not transactions:
                    return "无记录"
                latest_tx = max(transactions, key=lambda x: int(x["timeStamp"]))
                timestamp = int(latest_tx["timeStamp"])
                return datetime.fromtimestamp(timestamp + 8 * 3600, timezone.utc).strftime('%m-%d %H:%M:%S CST')
            elif data.get("status") == "0" and "No transactions found" in data.get("message", ""):
                return "无记录"
            else:
                pass
        except Exception as e:
            pass
        retry += 1
        time.sleep(min(2 ** retry, 10))  # 指数退避，最多sleep 10秒

def process_address_chunk(df, indices, lock, last_query_time, valid_addresses, need_check_count, need_check_list):
    for index in indices:
        with lock:
            elapsed = time.time() - last_query_time[0]
            if elapsed < 0.1:
                time.sleep(0.1 - elapsed)
            address = str(df.at[index, 'address']).strip()
            name = str(df.at[index, 'name']).strip()

            if not address or not Web3.is_address(address):
                df.drop(index, inplace=True)
                last_query_time[0] = time.time()
                continue

            print(f"正在查询 {name} 的地址: {address}")
            result = get_latest_internal_transaction_time(address, lock)

            while "API错误" in result:
                print(f"{name} API错误，正在重试...")
                time.sleep(0.5)
                result = get_latest_internal_transaction_time(address, lock)

            df.at[index, 'LastTXtime'] = result

            if result not in ["无记录", "无效地址", "API错误"]:
                valid_addresses[0] += 1
                if check_time_interval(result):
                    df.at[index, 'Status'] = '需检查'
                    need_check_count[0] += 1
                    need_check_list.append(name)
                else:
                    df.at[index, 'Status'] = ''
            else:
                df.at[index, 'Status'] = ''

            print(f"查询结果 - {name}: {result}, 状态: {df.at[index, 'Status']}")
            last_query_time[0] = time.time()

# 多线程处理地址
indices = list(range(len(df)))
chunk_size = len(indices) // 12 + (1 if len(indices) % 12 else 0)
chunks = [indices[i:i + chunk_size] for i in range(0, len(indices), chunk_size)]

lock = threading.Lock()
valid_addresses = [0]
need_check_count = [0]
need_check_list = []
last_query_time = [time.time()]

threads = []
for chunk in chunks:
    thread = threading.Thread(target=process_address_chunk, args=(df, chunk, lock, last_query_time, valid_addresses, need_check_count, need_check_list))
    threads.append(thread)
    thread.start()

for thread in threads:
    thread.join()

# 合约信息查询并计算变化量
for idx, row in df.iterrows():
    peer_id = str(row.get("peerID", "")).strip()
    if not peer_id or peer_id.lower() == "nan":
        continue
    try:
        total_rewards_list = contract.functions.getTotalRewards([peer_id]).call()
        total_wins = contract.functions.getTotalWins(peer_id).call()
        total_vote = contract.functions.getVoterVoteCount(peer_id).call()
        eoa_list = contract.functions.getEoa([peer_id]).call()
        eoa = eoa_list[0] if eoa_list else None

        df.at[idx, "TotalRewards"] = total_rewards_list[0] if total_rewards_list else None
        df.at[idx, "TotalWins"] = total_wins
        df.at[idx, "TotalVote"] = total_vote
        df.at[idx, "address"] = eoa # 合约信息查询和保存时，全部用address字段，不再处理EOA

        # 计算变化量
        # 获取之前的值，容错处理缺失列
        raw_prev_rewards = df_prev.get("TotalRewards", pd.Series([None] * len(df_prev))).at[idx]
        raw_prev_wins = df_prev.get("TotalWins", pd.Series([None] * len(df_prev))).at[idx]
        raw_prev_vote = df_prev.get("TotalVote", pd.Series([None] * len(df_prev))).at[idx]

        # 调试：打印原始历史值
        print(f"PeerID {peer_id[:12]}... 原始历史值 - 奖励: {raw_prev_rewards}, 胜利: {raw_prev_wins}, 投票: {raw_prev_vote}")

        prev_rewards = pd.to_numeric(raw_prev_rewards, errors='coerce')
        prev_rewards = int(prev_rewards) if pd.notna(prev_rewards) else 0
        prev_wins = pd.to_numeric(raw_prev_wins, errors='coerce')
        prev_wins = int(prev_wins) if pd.notna(prev_wins) else 0
        prev_vote = pd.to_numeric(raw_prev_vote, errors='coerce')
        prev_vote = int(prev_vote) if pd.notna(prev_vote) else 0

        # 调试：打印解析后的历史值
        print(f"PeerID {peer_id[:12]}... 解析后历史值 - 奖励: {prev_rewards}, 胜利: {prev_wins}, 投票: {prev_vote}")

        # 获取当前值，确保类型安全
        current_rewards = int(total_rewards_list[0]) if total_rewards_list and isinstance(total_rewards_list[0], (int, float)) and pd.notna(total_rewards_list[0]) else 0
        current_wins = int(total_wins) if isinstance(total_wins, (int, float)) and pd.notna(total_wins) else 0
        current_vote = int(total_vote) if isinstance(total_vote, (int, float)) and pd.notna(total_vote) else 0

        # 调试：打印当前值
        print(f"PeerID {peer_id[:12]}... 当前值 - 奖励: {current_rewards}, 胜利: {current_wins}, 投票: {current_vote}")

        # 计算变化量
        rewards_change = current_rewards - prev_rewards
        wins_change = current_wins - prev_wins
        vote_change = current_vote - prev_vote

        # 存储变化量：显示所有变化（正、负、零）
        df.at[idx, "RewardsChange"] = rewards_change if rewards_change != 0 else "无变化"
        df.at[idx, "WinsChange"] = wins_change if wins_change != 0 else "无变化"
        df.at[idx, "VoteChange"] = vote_change if vote_change != 0 else "无变化"

        # 如果是首次查询（prev 为 0 且 current 非 0），标记为"首次查询"
        if prev_rewards == 0 and current_rewards != 0:
            df.at[idx, "RewardsChange"] = "首次查询"
        if prev_wins == 0 and current_wins != 0:
            df.at[idx, "WinsChange"] = "首次查询"
        if prev_vote == 0 and current_vote != 0:
            df.at[idx, "VoteChange"] = "首次查询"

        # 格式化输出
        print("=== 合约查询结果 ===")
        print(f"[成功] PeerID {peer_id[:12]}...")
        print(f"  奖励: {current_rewards}")
        print(f"  胜利: {current_wins}")
        print(f"  投票: {current_vote}")
        print(f"  EOA: {eoa[:10]}..." if eoa else "  EOA: N/A")
        print(f"  变化 - 奖励: {df.at[idx, 'RewardsChange']}, 胜利: {df.at[idx, 'WinsChange']}, 投票: {df.at[idx, 'VoteChange']}")

    except Exception as e:
        print(f"[错误] 无法查询 PeerID {peer_id[:12]}...: {e}")

# 保存到原始 CSV 文件
try:
    # 保存所有列，包括自动补全的 address 和 EOA
    df.to_csv("address.csv", index=False, encoding="utf-8-sig")
    df.to_excel("address.xlsx", index=False)
except Exception as e:
    print(f"无法保存 CSV/Excel 文件: {e}")

# 输出统计信息
total_time = round(time.time() - start_time, 2)
query_speed = total_time / len(df) if len(df) > 0 else 0

print("\n=== 查询统计 ===")
print(f"查询完成，保存至 {CSV_FILE}")
print(f"总耗时: {total_time:.2f} 秒")
print(f"有效地址数: {valid_addresses[0]}")
print(f"需检查地址数: {need_check_count[0]}")
print(f"查询速度: {query_speed:.4f} 秒/地址")

if need_check_list:
    print("\n=== 需要检查的人员名单 ===")
    for name in need_check_list:
        print(f"- {name}")
else:
    print("\n没有需要检查的人员")

# 在程序结束时添加暂停
print("\n程序执行完成！")
input("按回车键退出...")