# Guide Développeur : Signature de Firmware via AWS KMS

Ce document explique comment un développeur autorisé peut signer un firmware localement sur sa machine, en utilisant la délégation de rôle AWS (`githubSigner`), tout en garantissant qu'aucune clé privée ne se trouve sur son disque dur.

## Pré-requis : Installation d'aws cli et Configuration des Credentials AWS

1. Installation d'aws cli sur Ubuntu / Debian

Suivre les instructions d'installation d'aws cli : https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

```bash
# Debian / Ubuntu
$ curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

```

2. **Vos clés d'accès permanentes**  
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

   Dans la suite du document, nous utiliserons le profil `default`.

3. **Délégation accordée par l'Admin**  
   L'administrateur Cloud doit vous avoir explicitement autorisé (via une policy IAM sur votre compte AWS) à assumer le rôle `githubSigner`.

4. Check aws connection en tant que développeur

```bash

$ aws sts get-caller-identity
{
    "UserId": "AIDAYZZGTFXY36K7NFXDH",
    "Account": "605134466545",
    "Arn": "arn:aws:iam::605134466545:user/bruxless-dev"
}

```

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

Pour Technoconcept, le numéro de compte AWS est : 605134466545 donc :

```ini
# Fichier : ~/.aws/config

[profile bruxless-signer]
role_arn = arn:aws:iam::605134466545:role/githubSigner
source_profile = default
region = eu-west-3
```

Check aws connection en tant que développeur avec le profil bruxless-signer

```bash

$ aws sts get-caller-identity --profile bruxless-signer
{
    "UserId": "AROAYZZGTFXYSQ5RXWWQV:botocore-session-1775808735",
    "Account": "605134466545",
    "Arn": "arn:aws:sts::605134466545:assumed-role/githubSigner/botocore-session-1775808735"
}

```

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

### Modification effectuées dans le dépot github

Dans le fichier `build.sh` ajout des 2 variables d'environnement :

```bash
# Set default AWS KMS signing variables if not provided by the environment (e.g. CI)
export AWS_PROFILE="${AWS_PROFILE:-bruxless-signer}"
export AWS_KMS_KEY_ID="${AWS_KMS_KEY_ID:-alias/sec/firmware-signer}"

```

- Ajout des fichiers :
  - `python/sign_firmware_aws_kms.py`
  - `python/publickey_ecdsa_aws.pem`
  - `python/verify_firmware_signature.py

- Modification du fichier `CMakeLists.txt`:

```cmake

    if(DEFINED ENV{AWS_KMS_KEY_ID})
        message(STATUS "Signing withAWS KMS Cloud Key.")
        list(APPEND _artifact_commands
            COMMAND ${PYTHON_SIGNING_INTERPRETER} ${CMAKE_CURRENT_LIST_DIR}/python/sign_firmware_aws_kms.py
                    --key-id "$ENV{AWS_KMS_KEY_ID}"
                    --firmware ${_bin_file}
                    --output ${_der_file}
        )

        list(APPEND _artifact_commands
            COMMAND ${PYTHON_SIGNING_INTERPRETER} ${CMAKE_CURRENT_LIST_DIR}/python/generate_nvpfwimage.py
                    ${_bin_file}
                    --unsigned-output ${_nvpfwimage_file}
                    --signed-output ${_nvpfwimage_file_signed}
                    --signature ${_der_file}

            COMMAND ${PYTHON_SIGNING_INTERPRETER} ${CMAKE_CURRENT_LIST_DIR}/python/verify_firmware_signature.py
                    --image ${_nvpfwimage_file_signed}
                    --public-key "${AWS_ECDSA_PUBLIC_KEY}"
                    
            COMMAND ${PYTHON_SIGNING_INTERPRETER} ${VISUALIZE_HEX_SCRIPT} ${_hex_file} --no-show
            COMMAND ${OBJSIZE} ${target_name}
        )

        add_custom_command(TARGET ${target_name} POST_BUILD
                ${_artifact_commands}
                COMMENT "Building ${_elf_file}, ${_hex_file}, ${_bin_file}, ${_map_file}, ${_nvpfwimage_file}, ${_nvpfwimage_file_signed}, and ECDSA signature")
    endif()
```
