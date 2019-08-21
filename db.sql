CREATE DATABASE ospedale;
USE ospedale;

--TABELLE
CREATE TABLE medico(
    cod_fiscale VARCHAR(16) NOT NULL,
    nome VARCHAR(256) NOT NULL,
    cognome VARCHAR(256) NOT NULL,
    anno_di_nascita DATE NOT NULL,

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
    anno_di_nascita DATE NOT NULL

    PRIMARY KEY(cod_fiscale)
)ENGINE = innodb;

CREATE TABLE specializzazione(
    nome VARCHAR(256) NOT NULL,
    descrizione VARCHAR(1000)

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

    PRIMARY KEY (id_lett, id_camera, reparto)
    FOREIGN KEY(id_letto, reparto) REFERENCES letto(id, reparto)
    FOREIGN KEY(id_camera, reparto) REFERENCES camera(id, reparto)
)ENGINE = innodb;

CREATE TABLE occupa_attualmente(
    paziente VARCHAR(16) NOT NULL,
    id_letto INTEGER NOT NULL,
    reparto VARCHAR(256) NOT NULL

    PRIMARY KEY(paziente)
    FOREIGN KEY(paziente) REFERENCES paziente(cod_fiscale)
        ON UPDATE NO ACTION ON DELETE CASCADE
    FOREIGN KEY(id_letto, reparto) REFERENCES letto(id, reparto)
)ENGINE = innodb;

CREATE TABLE ricovero_passato(
    paziente VARCHAR(16) NOT NULL,
    id_letto INTEGER NOT NULL,
    reparto VARCHAR(256) NOT NULL,
    data_ricovero DATE NOT NULL,
    data_dimissioni DATE NOT NULL

    PRIMARY KEY(paziente, letto, reparto, data_ricovero, data_dimissioni)
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

--indici
CREATE INDEX indice_paziente ON occupa_attualmente (paziente);