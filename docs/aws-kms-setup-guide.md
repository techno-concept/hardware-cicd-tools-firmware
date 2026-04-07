# Guide Administrateur : Paramétrage Sécurité AWS KMS

Ce document décrit pas à pas comment un administrateur Cloud ou Sécurité met en place la solution "Bring Your Own Key" (BYOK) dans AWS KMS pour signer les firmwares de manière sécurisée.

## Architecture

L'architecture repose sur un seul rôle IAM (`githubSigner`), assumé par les GitHub Actions via OIDC (pour l'intégration et le déploiement continu) et par les développeurs autorisés localement via leur compte AWS.

```mermaid
sequenceDiagram
    autonumber
    actor Admin as Administrateur Cloud/Sécu
    participant KMS as Service AWS KMS
    participant IAM as Service AWS IAM

    Admin->>KMS: Importation Clé ECC P-256 (BYOK)<br/>alias: alias/sec/firmware-signer
    KMS-->>Admin: Retourne ID Clé & ARN (KMS_KEY_ARN)

    Admin->>IAM: Création IAM Policy "AllowBruxlessKmsSign"<br/>(Action: kms:Sign, Ressource: KMS_KEY_ARN)
    IAM-->>Admin: Policy ARN

    Admin->>IAM: Création du rôle unique "githubSigner"<br/>Trust Policy duale:<br/>① sts:AssumeRoleWithWebIdentity → GitHub Actions (OIDC)<br/>② sts:AssumeRole → Admin/Dev IAM (tests locaux)
    Admin->>IAM: Attache "AllowBruxlessKmsSign" au rôle githubSigner
    IAM-->>Admin: Rôle configuré et prêt
```

## Étape 1 : Générer une clé de signature

Une clé ECC SECP256R1 (P-256) doit être générée sur une machine sécurisée et déconnectée d'Internet si possible.

Utilisez le script `generate-private-key.sh` :

```bash
# Génère par défaut private_key.der
./generate-private-key.sh

# Pour extraire la clé publique à fournir au firmware (bootloader) :
openssl ec -inform DER -in private_key.der -pubout -outform DER -out public_key.der
```

⚠️  **Sauvegardez `private_key.der` dans un système de gestion de secrets (comme Bitwarden/Vault) et supprimez-le de votre machine.** Il ne sera plus modifiable une fois importé et AWS ne le renverra jamais.

## Étape 2 : Importer la clé dans AWS KMS

Exécutez le script d'import avec un profil AWS disposant des droits administratifs. Ce script :

- Crée une "Master Key AWS" sans matériel de chiffrement.
- Récupère le certificat d'enveloppement (Wrapping Key).
- Chiffre votre `private_key.der` en transit.
- L'injecte sécuritairement, puis crée un alias pour cette clé.

➡️  Si vous souhaitez modifier le nom des fichiers ou l'alias, vous pouvez **éditer la section CONFIGURATION** au début du fichier `import-key-into-aws.sh`. **Attention**, l'alias choisi devra être rigoureusement le même dans `create-github-signer-role.sh`.

```bash
export AWS_PROFILE=bruxless-admin
export AWS_REGION=eu-west-3

./import-key-into-aws.sh
```

## Étape 3 : Créer les permissions et le rôle GitHub

Le script `create-github-signer-role.sh` va automatiser la création du fournisseur OIDC GitHub, de la politique de sécurité liant l'alias KMS créé ci-dessus, et du rôle `githubSigner`.

1. **Ouvrez `create-github-signer-role.sh`** dans votre éditeur de texte.
2. Modifiez la section **CONFIGURATION** en haut du fichier :
   - Ajoutez ou supprimez des dépôts GitHub autorisés dans le tableau `GITHUB_REPOS`.
   - Ajoutez les ARN des comptes développeurs dans le tableau `DEVELOPER_ARNS`.
3. **Exécutez le script** :

```bash
./create-github-signer-role.sh
```

## Étape 4 : Ajouter un Développeur à postériori

La gestion par OIDC/IAM n'utilise pas de mot de passe ni de "secret d'API longue durée". Si vous devez rajouter un nouvel employé :

1. Récupérez son ARN IAM (par exemple `arn:aws:iam::123456789012:user/prenom.nom`).
2. Ajoutez cette chaîne au tableau `DEVELOPER_ARNS` au début de `create-github-signer-role.sh`.
3. Ré-exécutez `./create-github-signer-role.sh`. Le script mettra à jour la *Trust Policy* IAM existante sans rien casser.
4. Orientez le développeur vers le fichier `aws-kms-developer-guide.md` afin qu'il puisse configurer son environnement de dev local.

```mermaid
sequenceDiagram
    autonumber
    actor Admin as Administrateur Cloud/Sécu
    actor Dev as Développeur
    participant IAM as Service AWS IAM

    Dev->>Admin: Demande d'accès à la signature locale<br/>(communique son ARN IAM : arn:aws:iam::XXXX:user/prenom.nom)

    Admin->>IAM: Met à jour la Trust Policy du rôle githubSigner via le script create-github-signer-role.sh
    IAM-->>Admin: Trust Policy mise à jour

    Admin->>Dev: Communique l'ARN du rôle et le lien vers la doc Dev
```

## Étape 5 : GitHub Actions (CI/CD Automatisation)

Une fois installé, le pipeline CI/CD n'aura besoin d'aucun mot de passe secret AWS statique.
GitHub échangera un jeton de courte durée contre des droits de signature.

```mermaid
sequenceDiagram
    autonumber
    actor Trigger as Push / Tag GitHub
    participant GH as GitHub Actions (Runner)
    participant OIDC as GitHub OIDC Provider
    participant STS as AWS STS
    participant KMS as AWS KMS

    Trigger->>GH: Déclenche le Release Workflow

    Note over GH, STS: Authentification sans secret (Keyless)
    GH->>OIDC: 1. Requête Token OIDC GitHub
    OIDC-->>GH: Token JWT signé<br/>(sub: repo:TechnoConcept/cross-...:refs/heads/main)

    GH->>STS: 2. AssumeRoleWithWebIdentity + JWT<br/>Rôle cible : githubSigner
    STS->>STS: Vérifie JWT + Trust Policy githubSigner
    STS-->>GH: ✅ Identifiants AWS temporaires

    Note over GH, KMS: Phase Build & Signature
    GH->>KMS: 3. kms:Sign(KeyId=alias/sec/firmware-signer, Message=Hash)

    KMS->>STS: githubSigner est-il autorisé ?
    STS-->>KMS: ✅ Oui (AllowBruxlessKmsSign)

    Note right of KMS: 🔑 KMS signe via HSM
    KMS-->>GH: Retourne la Signature

    GH-->>GH: ✅ Binaire signé & Artefact CI/CD publié
```
