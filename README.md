# SalaSync

Sala de assistir junto com salas públicas/privadas, perfil, chat em tempo real, YouTube e compartilhamento de arquivos. Frontend estático, com backend Supabase.

## Configurar o backend

1. Crie um projeto no Supabase.
2. No SQL Editor do projeto, execute o arquivo **supabase-setup.sql** completo.
3. Em Authentication → Sign In / Providers, habilite **Anonymous Sign-ins**. O site cria uma sessão anônima para cada navegador.
4. Copie o **Project URL** e a chave pública **Publishable / anon** nas configurações da API do projeto.
5. No arquivo **index.html**, preencha esta linha com os dados do seu projeto:

   window.SALASYNC_CONFIG = { url: '', key: '' };

   Coloque o Project URL entre as primeiras aspas e a chave pública entre as segundas. Isso permite que qualquer visitante conecte automaticamente ao mesmo backend.
6. Não coloque a chave **service_role** no site ou no GitHub. Use somente a chave pública e mantenha as políticas RLS do SQL.
7. Faça commit do arquivo e teste em outro navegador/dispositivo.

Também é possível usar o botão **Conectar** no site para configurar apenas aquele navegador; o site salva essas duas informações no armazenamento local do navegador.

## Publicação no GitHub Pages

1. No GitHub, abra **Settings → Pages**.
2. Escolha **GitHub Actions** como a origem da implantação.
3. Abra **Actions** e acompanhe o workflow **Deploy SalaSync to GitHub Pages** após um push para a branch **main**.
4. Depois de um deploy concluído e Pages ativado, o site deverá estar em:

   https://arthhenry87-crypto.github.io/AURORA/

## Funcionalidades

- Salas públicas e privadas; a senha da sala é guardada como hash no banco.
- Chat persistente com atualizações em tempo real.
- Perfil com nome e foto.
- YouTube compartilhado; o criador controla a reprodução.
- Upload privado de áudio e vídeo ao bucket `salasync-media`; os arquivos são servidos por URLs assinadas.
- Links de convite para entrar em uma sala privada e inserir a senha separadamente.

## Limites e notas de segurança

- O backend não está ativo até criar o projeto Supabase, executar o SQL, habilitar Anonymous Sign-ins e configurar a URL/chave pública.
- Autenticação anônima depende do navegador; limpar os dados locais pode encerrar a sessão.
- O site valida arquivos até 500 MB, mas o plano e as configurações de Storage do Supabase também impõem limites.
- Alguns vídeos não permitem incorporação ou reprodução automática.
- Compartilhe somente arquivos para os quais você tem direito de disponibilizar acesso.
