CREATE DATABASE ospedale;
USE ospedale;

--TABELLE
CREATE TABLE medico(
    cod_fiscale VARCHAR(16) NOT NULL,
    nome VARCHAR(256) NOT NULL,
    cognome VARCHAR(256) NOT NULL,
    anno_di_nascita INTEGER NOT NULL,

    PRIMARY KEY(cod_fiscale)
)ENGINE = innodb;

CREATE TABLE reparto(
    nome VARCHAR(256) NOT NULL,
    edificio INTEGER NOT NULL,
    letti_disponibili INTEGER NOT NULL,
    letti_occupati INTEGER NOT NULL,
    primario VARCHAR(16) NOT NULL,
    data_inizio DATE NOT NULL

    PRIMARY KEY(nome)
    FOREIGN key(primario) REFERENCES medico(cod_fiscale)
        ON UPDATE NO ACTION ON DELETE NO ACTION
)ENGINE = innodb;

CREATE TABLE camera(
    id INTEGER NOT NULL,
    reparto VARCHAR(256) NOT NULL

    PRIMARY KEY(id,reparto)
    FOREIGN KEY(reparto) REFERENCES reparto(nome)
)ENGINE = innodb;

CREATE TABLE letto(
    id INTEGER NOT NULL,
    reparto VARCHAR(256) NOT NULL

    PRIMARY KEY(id,reparto) 
    FOREIGN KEY(reparto) REFERENCES reparto(nome) 
        ON UPDATE NO ACTION ON DELETE CASCADE
)ENGINE = innodb;

CREATE TABLE paziente(
    cod_fiscale VARCHAR(16) NOT NULL,
    nome VARCHAR(256) NOT NULL,
    cognome VARCHAR(256) NOT NULL,
    anno_di_nascita INTEGER NOT NULL

    PRIMARY KEY(cod_fiscale)
)ENGINE = innodb;

CREATE TABLE specializzazione(
    nome VARCHAR(256) NOT NULL

    PRIMARY KEY(nome)
)ENGINE = innodb;

CREATE TABLE ha_ottenuto(
    medico VARCHAR(16) NOT NULL,
    specializzazione VARCHAR(256) NOT NULL

    PRIMARY KEY(medico)
    FOREIGN KEY(medico) REFERENCES medico(cod_fiscale)
        ON UPDATE NO ACTION ON DELETE CASCADE
)ENGINE = innodb;

CREATE TABLE afferisce(
    medico VARCHAR(16) NOT NULL,
    reparto VARCHAR(256) NOT NULL,

    PRIMARY KEY(medico),
    FOREIGN KEY(medico) REFERENCES medico(cod_fiscale)
        ON UPDATE NO ACTION ON DELETE CASCADE,
    FOREIGN KEY(reparto) REFERENCES reparto(nome) 
        ON UPDATE CASCADE ON DELETE NO ACTION --TODO
)ENGINE = innodb;

CREATE TABLE si_trova(
    id_letto INTEGER NOT NULL,
    id_camera INTEGER NOT NULL,
    reparto VARCHAR(256) NOT NULL

    PRIMARY KEY (id_letto, reparto)
    FOREIGN KEY(id_letto, reparto) REFERENCES letto(id, reparto)
    FOREIGN KEY(id_camera, reparto) REFERENCES camera(id, reparto)
)ENGINE = innodb;

CREATE TABLE occupa_attualmente(
    paziente VARCHAR(16) NOT NULL,
    id_letto INTEGER NOT NULL,
    reparto VARCHAR(256) NOT NULL,
    data_ricovero DATE

    PRIMARY KEY(paziente)
    FOREIGN KEY(paziente) REFERENCES paziente(cod_fiscale)
        ON DELETE CASCADE --TODO on update??
    FOREIGN KEY(id_letto, reparto) REFERENCES letto(id, reparto)
)ENGINE = innodb;

CREATE TABLE ricovero_passato(
    paziente VARCHAR(16) NOT NULL,
    id_letto INTEGER NOT NULL,
    reparto VARCHAR(256) NOT NULL,
    data_ricovero DATE NOT NULL,
    data_dimissioni DATE NOT NULL

    PRIMARY KEY(paziente, data_ricovero, data_dimissioni)
    FOREIGN KEY(paziente) REFERENCES paziente(cod_fiscale)
    FOREIGN KEY(id_letto, reparto) REFERENCES letto(id, reparto)
        ON DELETE NO ACTION
)ENGINE = innodb;

CREATE TABLE diagnosi(
    id INTEGER NOT NULL,
    medico VARCHAR(16) NOT NULL,
    paziente VARCHAR(16) NOT NULL,
    descrizione VARCHAR(1000),
    data_diagnosi DATE NOT NULL

    PRIMARY KEY(id, medico, paziente)
    FOREIGN KEY(medico) REFERENCES medico(cod_fiscale)
        ON DELETE NO ACTION
    FOREIGN KEY(paziente) REFERENCES paziente(cod_fiscale)
        ON DELETE NO ACTION --TODO
)ENGINE = innodb;

--indici TODO
CREATE INDEX indice_paziente ON occupa_attualmente (paziente);

--TRIGGER

DELIMITER $$
CREATE TRIGGER controlla_afferenza_primario
    BEFORE INSERT OR UPDATE ON reparto
    FOR EACH ROW
BEGIN
    DECLARE n int;
    DECLARE rep VARCHAR;
    SELECT COUNT(*) INTO n FROM reparto WHERE primario = NEW.primario;
    SELECT reparto INTO rep FROM afferisce WHERE cod_fiscale = NEW.primario; 
    IF ( n!=0 or rep != NEW.nome ) THEN
        RAISE NOTICE 'Hai inserito un primario non valido';
        return null;
    END IF;
    return NEW;
END$$
DELIMITER ;

CREATE OR REPLACE FUNCTION check_anno_nascita()
RETURNS TRIGGER LANGUAGE PLPGSQL AS
$$
BEGIN
    IF (NEW.anno_di_nascita >= 1993 or NEW.anno_di_nascita <= 1950) THEN
        RAISE NOTICE 'Hai inserito un anno di nascita non valido';
        return null;
    END IF;
    return new;
END;
$$;

DELIMITER $$
CREATE TRIGGER controlla_anno_nascita_medico
    BEFORE INSERT OR UPDATE ON medico
    FOR EACH ROW
    EXECUTE PROCEDURE check_anno_nascita()
$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER controlla_modifica_inserimento_camera
    BEFORE INSERT OR UPDATE ON si_trova
    FOR EACH ROW
BEGIN
    DECLARE rep VARCHAR;
    SELECT reparto INTO rep FROM camera WHERE NEW.id_camera = id;
    IF (NEW.reparto != rep) THEN
        RAISE NOTICE "Stai tentando di spostare/inserire il letto in un reparto che non è il suo";
        return null;
    END IF;
    return new;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER controllo_ricovero_dimissioni
    BEFORE INSERT ON ricovero_passato
    FOR EACH ROW
BEGIN
    IF(NEW.data_ricovero > NEW.data_dimissioni) THEN
        RAISE NOTICE "Hai inserito una data di ricovero che è sucessiva a quella delle dimissioni";
        return null;
    END IF;
    --TODO
    return NEW;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER controllo_inserimento_diagnosi
    BEFORE INSERT ON diagnosi
    FOR EACH ROW
BEGIN
    DECLARE reparto_medico varchar;
    DECLARE reparto_paziente_attuale varchar;
    DECLARE reparto_paziente_passato varchar;
    no_errori BOOLEAN := FALSE;
    SELECT reparto INTO reparto_medico FROM afferisce WHERE NEW.medico = medico;
    SELECT reparto INTO reparto_paziente_attuale FROM occupa_attualmente WHERE NEW.paziente = paziente;
    FOR reparto_paziente_passato IN
        SELECT reparto 
        FROM ricovero_passato 
        WHERE NEW.paziente = paziente LOOP
            IF (reparto_paziente_passato = reparto_medico ) THEN
                no_errori := TRUE;
                EXIT;
            END IF;
    END LOOP;

    IF (no_errori = FALSE AND reparto_medico != reparto_paziente_attuale) THEN 
        RAISE NOTICE "Hai inserito una diagnosi fatta da un medico il cui reparto non è quello in cui è (o è stato) ricoverato il paziente";
        return null;
    END IF;

    IF(NEW.medico = NEW.paziente) THEN
        RAISE NOTICE "Hai inserito lo stesso cf sia per medico che per paziente.";
        return null;
    END IF;

    return NEW;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER controllo_assegnazione_letto
    BEFORE INSERT OR UPDATE ON occupa_attualmente
    FOR EACH ROW
BEGIN
    DECLARE letto_occupato int;
    SELECT COUNT(*) INTO letto_occupato FROM occupa_attualmente WHERE NEW.id_letto = id_letto AND NEW.reparto = reparto;
    IF (letto_occupato = 1) THEN
        RAISE NOTICE "Il letto che stai cercando di assegnare è già occupato";
        return null;
    END IF;
    return NEW;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER update_letti_disponibili_occupati
    AFTER INSERT OR DELETE ON occupa_attualmente
    FOR EACH ROW
BEGIN
    DECLARE rep varchar;
    IF (TG_OP = 'INSERT') THEN
        rep := NEW.reparto;
        UPDATE reparto 
        SET letti_disponibili = letti_disponibili - 1, letti_occupati = letti_occupati + 1
        WHERE reparto.nome = rep;
    ELSEIF (TG_OP = 'DELETE') THEN
        rep := OLD.reparto;
        UPDATE reparto 
        SET letti_disponibili = letti_disponibili + 1, letti_occupati = letti_occupati - 1
        WHERE reparto.nome = rep;
    END IF;
END$$
DELIMITER ;






--DELIMITER $$
--CREATE TRIGGER controlla_letti_reparto
--    BEFORE INSERT OR UPDATE ON reparto
--    FOR EACH ROW
--BEGIN
--    DECLARE n int;
--    DECLARE n_2 int;
--    SELECT COUNT(*) INTO n FROM letto WHERE reparto = NEW.nome;
--    SELECT COUNT(*) INTO n_2 FROM occupa_attualmente WHERE reparto = NEW.nome;
--    IF ( n != NEW.letti_disponibili + NEW.letti_occupati ) THEN
--        RAISE NOTICE "Hai inserito un numero di letti disponibili e/o occupati errato";
--        return null;
--    END IF
--    IF (NEW.letti_occupati != )

