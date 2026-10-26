// Loaded by SupabaseAuth.gd only in the Godot Web export. Supabase's browser
// client owns OAuth PKCE, refresh, and its persistent browser session.
(() => {
	const bridge = {
		sdkReady: false,
		client: null,
		// session_checked turns true once Supabase has looked for a saved session (or failed to load),
		// so the game knows whether to show the entry screen or go straight to the menu.
		state: { ready: false, session_checked: false, signed_in: false, user: {}, profile: {}, decks: [], error: "", action: {} },
		configure(url, key) {
			if (!this.sdkReady || this.client) return;
			this.client = window.supabaseCreateClient(url, key, {
				auth: { autoRefreshToken: true, persistSession: true, detectSessionInUrl: true, flowType: "pkce" }
			});
			this.state.ready = true;
			this.client.auth.onAuthStateChange((event, session) => {
				if (event === "INITIAL_SESSION") this.state.session_checked = true;
				this.state.signed_in = !!session;
				this.state.user = session?.user ? {
					id: session.user.id,
					email: session.user.email || "",
					metadata: session.user.user_metadata || {}
				} : {};
				this.state.error = "";
				if (session && (event === "SIGNED_IN" || event === "INITIAL_SESSION" || event === "TOKEN_REFRESHED")) {
					setTimeout(() => { void bridge.refreshAccountData(); }, 0);
				} else if (!session) {
					this.state.profile = {};
					this.state.decks = [];
				}
			});
		},
		async signInGoogle() {
			if (!this.client) { this.state.error = "A conexão com Supabase ainda está iniciando."; return; }
			const { error } = await this.client.auth.signInWithOAuth({
				provider: "google",
				options: { redirectTo: window.location.href }
			});
			if (error) this.state.error = error.message;
		},
		async signOut() {
			if (!this.client) return;
			const { error } = await this.client.auth.signOut();
			if (error) this.state.error = error.message;
		},
		async refreshAccountData() {
			if (!this.client || !this.state.signed_in) return;
			const [profileResult, decksResult] = await Promise.all([
				this.client.from("profiles").select("id,username,display_name").single(),
				this.client.from("decks").select("id,name,content,created_at,updated_at").order("updated_at", { ascending: false })
			]);
			if (profileResult.error) this.state.error = profileResult.error.message;
			else this.state.profile = profileResult.data || {};
			if (decksResult.error) this.state.error = decksResult.error.message;
			else this.state.decks = decksResult.data || [];
		},
		async saveDeck(id, name, content) {
			if (!this.client || !this.state.signed_in) return this.finishAction("save_deck", null, "Entre com Google para salvar decks.");
			const row = { name, content };
			if (id) {
				const { data, error } = await this.client.from("decks").update(row).eq("id", id).select().single();
				this.finishAction("save_deck", data, error?.message || "");
			} else {
				row.user_id = this.state.user.id;
				const { data, error } = await this.client.from("decks").insert(row).select().single();
				this.finishAction("save_deck", data, error?.message || "");
			}
			if (!this.state.action.error) await this.refreshAccountData();
		},
		async deleteDeck(id) {
			if (!this.client || !this.state.signed_in) return this.finishAction("delete_deck", null, "Entre com Google para gerenciar decks.");
			const { error } = await this.client.from("decks").delete().eq("id", id);
			this.finishAction("delete_deck", { id }, error?.message || "");
			if (!error) await this.refreshAccountData();
		},
		async updateProfile(username, displayName) {
			if (!this.client || !this.state.signed_in) return this.finishAction("update_profile", null, "Entre com Google para editar o perfil.");
			const { data, error } = await this.client.from("profiles").update({ username, display_name: displayName }).eq("id", this.state.user.id).select().single();
			this.finishAction("update_profile", data, error?.message || "");
			if (!error) await this.refreshAccountData();
		},
		finishAction(kind, data, error) {
			this.state.action = { id: (this.state.action.id || 0) + 1, kind, data: data || {}, error };
			if (error) this.state.error = error;
		},
		getStateJson() { return JSON.stringify(this.state); }
	};
	window.CSAAuthBridge = bridge;
	import("https://esm.sh/@supabase/supabase-js@2")
		.then(({ createClient }) => { window.supabaseCreateClient = createClient; bridge.sdkReady = true; })
		.catch((error) => {
			bridge.state.error = "Não foi possível carregar o cliente Supabase: " + error.message;
			bridge.state.session_checked = true;
		});
})();
