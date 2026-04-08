# Guide Développeur : Signature de Firmware via AWS KMS

Ce document explique comment un développeur autorisé peut signer un firmware localement sur sa machine, en utilisant la délégation de rôle AWS (`githubSigner`), tout en garantissant qu'aucune clé privée ne se trouve sur son disque dur.

## Pré-requis : Configuration des Credentials AWS

1. **Vos clés d'accès permanentes**  
   L'administrateur AWS doit vous fournir une clé d'accès (Access Key ID et Secret Access Key). Ces identifiants prouvent votre identité mais n'ont *pas* le droit direct de signer.  
   Configurez ces identifiants dans votre fichier `~/.aws/credentials` :

   ```ini
   # Fichier : ~/.aws/credentials
   
   # Option A : Profil par défaut
   [default]
   aws_access_key_id = AKIAIOSFODNN7EXAMPLE
   aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
   
   # Option B : Profil dédié nommé (ex: bruxless-dev)
   [bruxless-dev]
   aws_access_key_id = AKIAIOSFODNN7EXAMPLE
   aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
   ```

2. **Délégation accordée par l'Admin**  
   L'administrateur Cloud doit vous avoir explicitement autorisé (via une policy IAM sur votre compte AWS) à assumer le rôle `githubSigner`.

## Configuration Initiale du Profil Signer (AssumeRole)

Afin d'endosser dynamiquement le rôle autorisé à lancer une opération de signature, AWS supporte nativement la création d'un "profil délégué" dans `~/.aws/config`. Ce profil va utiliser vos credentials de base pour "assumer" (emprunter) temporairement les droits du rôle `githubSigner`.

Ouvrez le fichier `~/.aws/config` (et non `credentials`) et ajoutez ces lignes :

```ini
# Fichier : ~/.aws/config

[profile bruxless-signer]
role_arn = arn:aws:iam::VOTRE_AWS_ACCOUNT_ID:role/githubSigner
source_profile = default
region = eu-west-3
```

- **`role_arn`** : Remplacez `VOTRE_AWS_ACCOUNT_ID_12_CHIFFRES` par le numéro de compte AWS de l'entreprise (ex: 123456789012).
- **`source_profile`** : Mettez ici le nom du profil utilisé dans `~/.aws/credentials` (ex: `default` ou `bruxless-dev`).

## Signature du Firmware au quotidien

Lorsque la configuration est en place et que votre ARN a bien été autorisé, le profil basculera les rôles automatiquement tout en limitant les privilèges uniquement aux actes de signature pendant `1 Heure`.

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Développeur (Local)
    participant script as Script (Python/Bash)
    participant STS as AWS STS
    participant KMS as AWS KMS

    Note over Dev, STS: Authentification via Assume Role
    Dev->>STS: AWS CLI/SDK assume githubSigner<br/>(profil bruxless-signer)
    STS-->>Dev: Identifiants temporaires (valides 1h)

    Note over Dev, KMS: Processus de Signature
    Dev->>script: Lancement du script de signare --profile bruxless-signer
    script->>script: 1. Calcule le Hash SHA-256 du binaire firmware

    script->>KMS: kms.sign(KeyId, Message=Hash, MessageType='DIGEST')
    KMS->>STS: Vérifie que githubSigner a la permission
    STS-->>KMS: ✅ Autorisé

    Note right of KMS: 🔑 Signature en mémoire HSM sécurisée<br/>(Exfiltration de la clé privée IMPOSSIBLE)
    KMS-->>script: Retourne la Signature (bytes)

    script->>script: 2. Sauvegarde la signature (ex: app.sig)
    script-->>Dev: ✅ Firmware signé avec succès
```

**Légende :**
1. Le SDK (ou le script CLI) intercepte le `profile bruxless-signer` et demande automatiquement à AWS STS d'emprunter temporairement le rôle `githubSigner` via vos identifiants configurés.
2. AWS STS retourne un accès temporaire (limité à 1 heure).
3. Vous lancez le script de signature python en ligne de commande.
4. Ce dernier lit le firmware et calcule l'empreinte locale (Hash SHA-256).
5. Le script transmet l'empreinte du fichier à l'API AWS KMS avec les autorisations temporaires.
6. KMS interroge IAM pour vérifier si votre identité empruntée a l'autorisation (Policy Attachée).
7. L'accès en signature de `githubSigner` est confirmé.
8. La clé matérielle privée KMS signe de manière HSM l'empreinte et ne quitte jamais le coffre-fort cloud d'Amazon.
9. La signature au format standard est renvoyée sur la machine d'exécution locale.
10. Le script sauvegarde le bloc de signature dans un fichier (ex: `app.sig`).
11. Le développeur valide que le process de signature est terminé et que son firmware est prêt.

### Exemple avec AWS CLI depuis un script Python (ou autre SDK)

> [!NOTE]
> Le script `sign_firmware_aws.py` mentionné ci-dessous est un exemple d'intégration. Il n'est pas fourni par défaut dans ce dépôt mais illustre comment appeler l'API AWS KMS Sign via un SDK (boto3, etc.).

Si vous disposez d'un script `sign_firmware_aws.py` :

```bash
# Exportez le bon profil local avant le lancement de votre script
export AWS_PROFILE=bruxless-signer

# Le SDK s'authentifiera automatiquement auprès d'AWS IAM pour générer un jeton temporaire depuis votre compte
python3 ./sign_firmware_aws.py \
  --key-id alias/sec/firmware-signer \
  --firmware firmware-build.bin \
  --region eu-west-3
```

L'unique moyen d'obtenir une signature valide au format convenu (pour le Bootloader) et donc avec ces identifiants cryptographiques sécurisés, est de passer par votre identité AWS. La compromission du PC d'un développeur ne peut en aucun cas faire fuir la clé "maître".
