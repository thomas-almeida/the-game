"""
Agent Communication Bus (MCP Server & CLI)
Permite que múltiplos agentes e terminais paralelos do Antigravity troquem mensagens,
atualizem tarefas e consultem o status do projeto em tempo real.
"""

import sys
import os
import json
import sqlite3
import argparse
from datetime import datetime

# Garante que o diretório de dados existe
DB_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".agent_bus")
DB_PATH = os.path.join(DB_DIR, "bus.db")


def get_db():
    os.makedirs(DB_DIR, exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=10.0)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("""
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            from_agent TEXT NOT NULL,
            to_agent TEXT NOT NULL,
            subject TEXT,
            body TEXT NOT NULL,
            is_read INTEGER DEFAULT 0
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS status_board (
            agent TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            current_task TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)
    conn.commit()
    return conn


def send_message(from_agent: str, to_agent: str, subject: str, body: str) -> dict:
    conn = get_db()
    now = datetime.now().isoformat(timespec="seconds")
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO messages (timestamp, from_agent, to_agent, subject, body, is_read) VALUES (?, ?, ?, ?, ?, 0)",
        (now, from_agent, to_agent, subject or "", body),
    )
    msg_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return {
        "status": "success",
        "message_id": msg_id,
        "from": from_agent,
        "to": to_agent,
        "subject": subject,
        "timestamp": now,
    }


def read_inbox(agent_name: str, mark_read: bool = True) -> list:
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT id, timestamp, from_agent, to_agent, subject, body, is_read
        FROM messages
        WHERE (to_agent = ? OR to_agent = 'all')
        ORDER BY id ASC
        """,
        (agent_name,),
    )
    rows = cursor.fetchall()
    messages = []
    unread_ids = []
    for r in rows:
        messages.append({
            "id": r[0],
            "timestamp": r[1],
            "from": r[2],
            "to": r[3],
            "subject": r[4],
            "body": r[5],
            "is_read": bool(r[6]),
        })
        if not r[6]:
            unread_ids.append(r[0])

    if mark_read and unread_ids:
        cursor.execute(
            f"UPDATE messages SET is_read = 1 WHERE id IN ({','.join(['?']*len(unread_ids))})",
            unread_ids,
        )
        conn.commit()

    conn.close()
    return messages


def update_status(agent_name: str, status: str, current_task: str) -> dict:
    conn = get_db()
    now = datetime.now().isoformat(timespec="seconds")
    cursor = conn.cursor()
    cursor.execute(
        """
        INSERT INTO status_board (agent, status, current_task, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(agent) DO UPDATE SET
            status = excluded.status,
            current_task = excluded.current_task,
            updated_at = excluded.updated_at
        """,
        (agent_name, status, current_task, now),
    )
    conn.commit()
    conn.close()
    return {
        "status": "success",
        "agent": agent_name,
        "new_status": status,
        "task": current_task,
        "updated_at": now,
    }


def get_board(limit: int = 10) -> dict:
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT agent, status, current_task, updated_at FROM status_board ORDER BY updated_at DESC")
    agents = [
        {"agent": r[0], "status": r[1], "current_task": r[2], "updated_at": r[3]}
        for r in cursor.fetchall()
    ]
    cursor.execute(
        """
        SELECT id, timestamp, from_agent, to_agent, subject, body, is_read
        FROM messages
        ORDER BY id DESC LIMIT ?
        """,
        (limit,),
    )
    recent_messages = [
        {
            "id": r[0],
            "timestamp": r[1],
            "from": r[2],
            "to": r[3],
            "subject": r[4],
            "body": r[5],
            "is_read": bool(r[6]),
        }
        for r in cursor.fetchall()
    ]
    conn.close()
    return {
        "agents": agents,
        "recent_messages": recent_messages,
    }


# ==========================================
# MCP Protocol Handlers (JSON-RPC 2.0 Stdio)
# ==========================================

TOOLS = [
    {
        "name": "agent_bus_send",
        "description": "Envia uma mensagem ou tarefa para outro agente ('orquestrador', 'mecanicas', 'cena', 'interface') ou para 'all' (broadcast).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "from_agent": {
                    "type": "string",
                    "description": "Nome do agente remetente (ex: 'orquestrador', 'mecanicas', 'cena', 'interface')",
                },
                "to_agent": {
                    "type": "string",
                    "description": "Nome do agente destinatário ou 'all' para broadcast",
                },
                "subject": {
                    "type": "string",
                    "description": "Assunto ou título curto da mensagem/tarefa",
                },
                "body": {
                    "type": "string",
                    "description": "Conteúdo detalhado da mensagem, instrução ou relatório",
                },
            },
            "required": ["from_agent", "to_agent", "body"],
        },
    },
    {
        "name": "agent_bus_read_inbox",
        "description": "Lê a caixa de entrada de mensagens do agente especificado.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "agent_name": {
                    "type": "string",
                    "description": "Nome do agente cuja caixa de entrada deve ser lida",
                },
                "mark_read": {
                    "type": "boolean",
                    "description": "Se verdadeiro, marca as mensagens lidas como concluídas/lidas. Padrão: true.",
                },
            },
            "required": ["agent_name"],
        },
    },
    {
        "name": "agent_bus_update_status",
        "description": "Atualiza o status e a tarefa atual do agente no quadro geral de agentes.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "agent_name": {
                    "type": "string",
                    "description": "Nome do agente (ex: 'orquestrador', 'mecanicas', 'cena', 'interface')",
                },
                "status": {
                    "type": "string",
                    "description": "Status atual (ex: 'idle', 'executando', 'aguardando_integracao', 'concluido')",
                },
                "current_task": {
                    "type": "string",
                    "description": "Descrição sucinta da tarefa em andamento",
                },
            },
            "required": ["agent_name", "status", "current_task"],
        },
    },
    {
        "name": "agent_bus_get_board",
        "description": "Retorna o quadro geral de status de todos os agentes e as mensagens recentes trocadas.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "limit": {
                    "type": "integer",
                    "description": "Número máximo de mensagens recentes a exibir. Padrão: 10.",
                }
            },
        },
    },
]


def run_mcp_server():
    """Lê JSON-RPC de stdin e escreve em stdout conforme a especificação do MCP."""
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue

        try:
            req = json.loads(line)
        except Exception:
            continue

        req_id = req.get("id")
        method = req.get("method")
        params = req.get("params", {})

        # Notificações não precisam de resposta
        if req_id is None:
            continue

        if method == "initialize":
            res = {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "serverInfo": {
                        "name": "the-game-agent-bus",
                        "version": "1.0.0",
                    },
                },
            }
            sys.stdout.write(json.dumps(res) + "\n")
            sys.stdout.flush()

        elif method == "ping":
            res = {"jsonrpc": "2.0", "id": req_id, "result": {}}
            sys.stdout.write(json.dumps(res) + "\n")
            sys.stdout.flush()

        elif method == "tools/list":
            res = {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {"tools": TOOLS},
            }
            sys.stdout.write(json.dumps(res) + "\n")
            sys.stdout.flush()

        elif method == "tools/call":
            tool_name = params.get("name")
            args = params.get("arguments", {})
            try:
                if tool_name == "agent_bus_send":
                    output = send_message(
                        from_agent=args.get("from_agent"),
                        to_agent=args.get("to_agent"),
                        subject=args.get("subject", ""),
                        body=args.get("body"),
                    )
                elif tool_name == "agent_bus_read_inbox":
                    output = read_inbox(
                        agent_name=args.get("agent_name"),
                        mark_read=args.get("mark_read", True),
                    )
                elif tool_name == "agent_bus_update_status":
                    output = update_status(
                        agent_name=args.get("agent_name"),
                        status=args.get("status"),
                        current_task=args.get("current_task"),
                    )
                elif tool_name == "agent_bus_get_board":
                    output = get_board(limit=args.get("limit", 10))
                else:
                    output = {"error": f"Ferramenta desconhecida: {tool_name}"}

                res = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "content": [
                            {"type": "text", "text": json.dumps(output, indent=2, ensure_ascii=False)}
                        ],
                        "isError": "error" in output if isinstance(output, dict) else False,
                    },
                }
            except Exception as e:
                res = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "content": [{"type": "text", "text": f"Erro interno: {str(e)}"}],
                        "isError": True,
                    },
                }
            sys.stdout.write(json.dumps(res) + "\n")
            sys.stdout.flush()

        else:
            res = {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32601, "message": f"Método não encontrado: {method}"},
            }
            sys.stdout.write(json.dumps(res) + "\n")
            sys.stdout.flush()


# ==========================================
# CLI Subcommands (Para uso manual no shell)
# ==========================================

def main():
    # Se nenhum argumento for passado ou for --mcp, inicia servidor MCP
    if len(sys.argv) == 1 or (len(sys.argv) == 2 and sys.argv[1] == "--mcp"):
        run_mcp_server()
        return

    parser = argparse.ArgumentParser(description="Barramento de Comunicação entre Agentes Antigravity")
    subparsers = parser.add_subparsers(dest="cmd")

    # Send
    send_p = subparsers.add_parser("send", help="Envia mensagem para outro agente")
    send_p.add_argument("--from", dest="from_agent", required=True, help="Remetente")
    send_p.add_argument("--to", dest="to_agent", required=True, help="Destinatário ('all' para broadcast)")
    send_p.add_argument("--subject", default="", help="Assunto")
    send_p.add_argument("--body", required=True, help="Corpo da mensagem")

    # Read
    read_p = subparsers.add_parser("read", help="Lê mensagens da caixa de entrada")
    read_p.add_argument("--agent", required=True, help="Nome do agente")
    read_p.add_argument("--peek", action="store_true", help="Não marca mensagens como lidas")

    # Status
    status_p = subparsers.add_parser("status", help="Atualiza status do agente")
    status_p.add_argument("--agent", required=True, help="Nome do agente")
    status_p.add_argument("--state", required=True, help="Estado (ex: idle, trabalhando, pronto)")
    status_p.add_argument("--task", required=True, help="Tarefa atual")

    # Board
    board_p = subparsers.add_parser("board", help="Exibe o quadro de agentes e últimas mensagens")
    board_p.add_argument("--limit", type=int, default=10, help="Quantidade de mensagens")

    args = parser.parse_args()

    if args.cmd == "send":
        res = send_message(args.from_agent, args.to_agent, args.subject, args.body)
        print(f"[OK] Mensagem #{res['message_id']} enviada de '{args.from_agent}' para '{args.to_agent}'.")
    elif args.cmd == "read":
        msgs = read_inbox(args.agent, mark_read=not args.peek)
        if not msgs:
            print(f"Nenhuma mensagem para '{args.agent}'.")
        else:
            print(f"--- Caixa de entrada de '{args.agent}' ({len(msgs)} mensagem(ns)) ---")
            for m in msgs:
                status_icon = "LIDA" if m["is_read"] else "NOVA"
                print(f"[{m['timestamp']}] #{m['id']} [{status_icon}] De: {m['from']} -> Assunto: {m['subject']}")
                print(f"    {m['body']}\n")
    elif args.cmd == "status":
        res = update_status(args.agent, args.state, args.task)
        print(f"[OK] Status de '{args.agent}' atualizado para '{args.state}': {args.task}")
    elif args.cmd == "board":
        b = get_board(args.limit)
        print("=== QUADRO DE AGENTES ===")
        for a in b["agents"]:
            print(f"[{a['updated_at']}] {a['agent'].upper()}: [{a['status']}] - {a['current_task']}")
        print("\n=== MENSAGENS RECENTES ===")
        for m in b["recent_messages"]:
            print(f"[{m['timestamp']}] De: {m['from']} Para: {m['to']} | Assunto: {m['subject']}")
            print(f"    {m['body']}")


if __name__ == "__main__":
    main()
