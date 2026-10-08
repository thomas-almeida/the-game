# Protocolo de Comunicação entre Agentes

Todos os terminais paralelos do Antigravity utilizam o servidor MCP **`agent-bus`** (implementado em `tools/agent_bus_mcp.py`) para trocar mensagens, coordenar tarefas e reportar alterações ao **orquestrador**.

---

## 1. Ferramentas MCP Disponíveis

Quando uma sessão do Antigravity é iniciada, as seguintes ferramentas estão disponíveis:

### `agent_bus_send`
Envia uma mensagem direta ou tarefa para outro agente ou para todos (`all`).
* `from_agent`: Nome do remetente (`orquestrador`, `mecanicas`, `cena`, `interface`)
* `to_agent`: Destinatário (`orquestrador`, `mecanicas`, `cena`, `interface` ou `all`)
* `subject`: Assunto / título da tarefa
* `body`: Detalhes, instruções ou relatório de entrega

### `agent_bus_read_inbox`
Lê as mensagens recebidas na caixa de entrada do agente.
* `agent_name`: Nome do agente consultando sua caixa (`orquestrador`, `cena`, etc.)
* `mark_read`: Se `true` (padrão), marca as mensagens como lidas após leitura.

### `agent_bus_update_status`
Atualiza o status de trabalho no quadro geral de agentes.
* `agent_name`: Nome do agente
* `status`: Ex.: `idle`, `trabalhando`, `aguardando_integracao`, `concluido`
* `current_task`: Descrição sucinta da tarefa em andamento

### `agent_bus_get_board`
Consulta o quadro geral com o status atual de todos os agentes e as últimas mensagens trocadas.

---

## 2. Linha de Comando (CLI alternativa)

Qualquer agente ou operador humano no PowerShell pode interagir diretamente com o barramento via terminal:

```powershell
# Enviar mensagem / solicitação ao orquestrador
python tools/agent_bus_mcp.py send --from cena --to orquestrador --subject "Lanes criadas" --body "Lanes implementadas em farm_3d.gd. Preciso que main_3d.gd instancie a cena."

# Ler mensagens pendentes para o seu agente
python tools/agent_bus_mcp.py read --agent mecanicas

# Atualizar seu status de trabalho
python tools/agent_bus_mcp.py status --agent cena --state trabalhando --task "Ajustando materiais dos slimes"

# Ver quadro geral do projeto
python tools/agent_bus_mcp.py board
```

---

## 3. Fluxo de Trabalho com o Orquestrador

1. O **orquestrador** posta as tarefas de cada agente via `agent_bus_send`.
2. O agente (`mecanicas`, `cena` ou `interface`) lê sua inbox (`agent_bus_read_inbox`) e atualiza seu status (`agent_bus_update_status`).
3. Ao concluir suas alterações nos seus arquivos permitidos (conforme `invariantes.md`), o agente reporta ao `orquestrador` com o que precisa ser integrado no `main_3d.gd` e as medições de teste.
4. O **orquestrador** lê os relatórios, integra em `main_3d.gd`, executa os testes de validação (`load_check.tscn` e `sim.gd`) e confirma a conclusão.
