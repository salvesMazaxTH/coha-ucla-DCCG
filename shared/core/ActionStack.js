/**
 * ActionStack.js
 * Gerencia a ordem de execução de efeitos e eventos.
 * Garante que efeitos em cadeia (triggers) sejam processados antes da próxima ação do jogador.
 */
export class ActionStack {
  constructor() {
    this.queue = [];
    this.isProcessing = false;
  }

  // Adiciona uma ação ou efeito à fila
  push(actionFn, context = {}) {
    this.queue.push({ actionFn, context });
    if (!this.isProcessing) {
      this.process();
    }
  }

  async process() {
    this.isProcessing = true;

    while (this.queue.length > 0) {
      const { actionFn, context } = this.queue.shift();

      try {
        // Executa a função (pode ser async para suportar lógica complexa)
        await actionFn(context);
      } catch (error) {
        console.error("Erro ao processar ActionStack:", error);
      }
    }

    this.isProcessing = false;
  }
}
