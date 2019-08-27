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
    piano INTEGER NOT NULL,
    letti_disponibili INTEGER NOT NULL,
    letti_occupati INTEGER NOT NULL,
    primario VARCHAR(16) NOT NULL,
    data_inizio DATE NOT NULL,

    PRIMARY KEY (nome),
    FOREIGN KEY (primario) REFERENCES medico (cod_fiscale)
        ON UPDATE NO ACTION ON DELETE NO ACTION
)ENGINE = innodb;

CREATE TABLE camera(
    id VARCHAR(2) NOT NULL,
    reparto VARCHAR(256) NOT NULL,

    PRIMARY KEY(id,reparto),
    FOREIGN KEY(reparto) REFERENCES reparto(nome)
)ENGINE = innodb;

CREATE TABLE letto(
    id INTEGER NOT NULL,
    reparto VARCHAR(256) NOT NULL,

    PRIMARY KEY(id,reparto), 
    FOREIGN KEY(reparto) REFERENCES reparto(nome) 
        ON UPDATE NO ACTION ON DELETE CASCADE
)ENGINE = innodb;

CREATE TABLE paziente(
    cod_fiscale VARCHAR(16) NOT NULL,
    nome VARCHAR(256) NOT NULL,
    cognome VARCHAR(256) NOT NULL,
    anno_di_nascita INTEGER NOT NULL,

    PRIMARY KEY(cod_fiscale)
)ENGINE = innodb;

CREATE TABLE specializzazione(
    nome VARCHAR(256) NOT NULL,

    PRIMARY KEY(nome)
)ENGINE = innodb;

CREATE TABLE ha_ottenuto(
    medico VARCHAR(16) NOT NULL,
    specializzazione VARCHAR(256) NOT NULL,

    PRIMARY KEY(medico),
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
        ON UPDATE CASCADE ON DELETE CASCADE
)ENGINE = innodb;

CREATE TABLE si_trova(
    id_letto INTEGER NOT NULL,
    id_camera VARCHAR(1) NOT NULL,
    reparto VARCHAR(256) NOT NULL,

    PRIMARY KEY (id_letto, reparto),
    FOREIGN KEY(id_letto, reparto) REFERENCES letto(id, reparto),
    FOREIGN KEY(id_camera, reparto) REFERENCES camera(id, reparto)
)ENGINE = innodb;

CREATE TABLE occupa_attualmente(
    paziente VARCHAR(16) NOT NULL,
    id_letto INTEGER NOT NULL,
    reparto VARCHAR(256) NOT NULL,
    data_ricovero DATE,

    PRIMARY KEY(paziente),
    FOREIGN KEY(paziente) REFERENCES paziente(cod_fiscale),
        ON DELETE CASCADE --TODO on update?
    FOREIGN KEY(id_letto, reparto) REFERENCES letto(id, reparto)
)ENGINE = innodb;

CREATE TABLE ricovero_passato(
    paziente VARCHAR(16) NOT NULL,
    id_letto INTEGER NOT NULL,
    reparto VARCHAR(256) NOT NULL,
    data_ricovero DATE NOT NULL,
    data_dimissioni DATE NOT NULL,

    PRIMARY KEY(paziente, data_ricovero, data_dimissioni),
    FOREIGN KEY(paziente) REFERENCES paziente(cod_fiscale),
    FOREIGN KEY(id_letto, reparto) REFERENCES letto(id, reparto)
        ON DELETE NO ACTION
)ENGINE = innodb;

CREATE TABLE diagnosi(
    id INTEGER IDENTITY(1,1),
    medico VARCHAR(16) NOT NULL,
    paziente VARCHAR(16) NOT NULL,
    descrizione VARCHAR(1000),

    PRIMARY KEY(id, medico, paziente),
    FOREIGN KEY(medico) REFERENCES medico(cod_fiscale)
        ON DELETE NO ACTION,
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
    SELECT reparto INTO rep FROM afferisce WHERE cod_fiscale = NEW.primario;
    SELECT COUNT(*) INTO n FROM reparto WHERE primario = NEW.primario;

    IF (TG_OP = 'INSERT') THEN
        IF (n > 0) THEN
            RAISE NOTICE "Il primario inserito risulta già primario in un altro reparto";
            return null;
        END IF;
    ELSEIF (TG_OP = 'UPDATE') THEN
        IF ( NEW.primario != OLD.primario ) THEN
            IF (n > 0) THEN
                RAISE NOTICE "Il primario inserito risulta già primario in un altro reparto";
                return null;
            ELSEIF ( NEW.nome != rep ) THEN
                RAISE NOTICE "Il primario che stai inserendo afferisce ad un altro reparto. 
                Un medico può essere primario solo del reparto in cui afferisce";
                return null;
            END IF;
        END IF;
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


INSERT INTO medico (cod_fiscale, nome, cognome, anno_di_nascita) VALUES 
('0000000000000000', 'Palmiro', 'Ullari', 1967),
('0000000000000001', 'Pamela', 'Rossi', 1964),
('0000000000000002', 'Giorgio', 'Verdi', 1962),
('1390252630529852', 'Gianni', 'Sperti', 1962),
('5397339808043402', 'Mario', 'Verdi', 1972),
('8983816935854044', 'Mirko', 'Vecchio', 1971),
('1846685306030041', 'Mirko', 'Vanni', 1961),
('3359386196812767', 'Marco', 'Vecchioni', 1980),
('8229483796548314', 'Matteo', 'Comello', 1991),
('9986551251591601', 'Mirko', 'Vecchio', 1971),
('9986551251591602', 'Chiara', 'Darsie', 1992),
('6270315354617646', 'Eros', 'Fabrici', 1990),
('9532264530953180', 'Ines', 'Ovuka', 1992),
('9722043314326266', 'Emilia', 'Regrutto', 1982),
('5247566716900138', 'Eugenia', 'Nascimbeni', 1982),
('1846344461747046', 'Liana', 'Garofalo', 1982),
('5064900651193446', 'Giustina', 'Guerra', 1970),
('3870666939878725', 'Luca', 'Gatto', 1982),
('7612457177395462', 'Licia', 'Guarrera', 1982),
('8823711966847212', 'Mario', 'Nuoro', 1969),
('4972751419368561', 'Leone', 'Belluomo', 1969),
('4453712641026329', 'Fabio', 'Vanin', 1992),
('2846065032302035', 'Gianni', 'Lucis', 1970),
('7477983483987465', 'Giada', 'Lucchetta', 1981),
('6427536181858392', 'Giacomo', 'Bianchi', 1971),
('1069677691745915', 'Giulia', 'Porisiensi', 1971),
('7517724820974182', 'Sara', 'Bianco', 1979),
('6182593637417854', 'Lucia', 'Campana', 1965),
('5370097283258201', 'Sergio', 'Porisiensi', 1960),
('5856455334849193', 'Fabio', 'Darsie', 1962),
('2219722864301108', 'Mariassunta', 'Dalla Cia', 1964),
('7222181464671416', 'Alessandro', 'Darsie', 1976);




INSERT INTO paziente (cod_fiscale, nome, cognome, anno_di_nascita) VALUES 
('0000000000000000', 'Palmiro', 'Ullari', 1967),
('0000000000000001', 'Pamela', 'Rossi', 1964),
('0000000000000002', 'Giorgio', 'Verdi', 1962),
('8225751935680501', 'Maria Pia', 'Tonon', 1940),
('4224355445461313', 'Carmela', 'Roveda', 1938),
('6337027164120347', 'Carmine', 'Rossi', 1948),
('7331442932981994', 'Carola', 'Ronchi', 1998),
('1868936191486718', 'Bruno', 'Dalla Cia', 1938),
('6814449000846526', 'Giuseppe', 'Dalla Cia', 1970),
('4077100134185992', 'Dimitri', 'Dalla Cia', 2006),
('8010657258419520', 'Maria', 'Dallava', 1998),
('4418933657981244', 'Marco', 'Dalle Vedove', 2000),
('6627897026222284', 'Marta', 'Dallava', 1975),
('6438139634395960', 'Michela', 'Santin', 1993),
('7653062108131006', 'Maria', 'Santina', 1989),
('5588574605730229', 'Mariateresa', 'Dalla', 1968),
('2720222047038703', 'Teresa', 'Muggia', 1966),
('5627971602753923', 'Valentina', 'Ricci', 1978),
('8346800316953369', 'Valeria', 'Riccio', 1966),
('9337383323309168', 'Valentina', 'Ricciardi', 1990),
('9410825649373196', 'Valerio', 'Rossi', 1955),
('7096793081288325', 'Valerio', 'Scanu', 1983),
('8524011104695532', 'Egidio', 'Darsie', 1939),
('8936419229711070', 'Paola', 'Rossi', 1955),
('9735563994270860', 'Italo', 'Santin', 1950),
('3170891874979344', 'Italino', 'Rombi', 1965),
('9274115114979232', 'Valeria', 'Rusnik', 1980),
('1308368971707572', 'Vanna', 'Killo', 1988),
('7101809454382081', 'Rudy', 'Conte', 1992),
('5701623795430872', 'Enrico', 'Macorig', 2001),
('6506917832305512', 'Sofia', 'Valdes', 1995),
('6883649214252943', 'Vanni', 'Palu', 1945),
('1359567119628313', 'Mario', 'Esposito', 1951),
('6556042443923494', 'Valerio', 'Esposto', 1955),
('8965488863765894', 'Luca', 'Spagnol', 1965),
('7730531723964112', 'Lucia', 'Spagnoli', 1967),
('1979758501449854', 'Rita', 'Spagna', 1973),
('3183465973212040', 'Luca', 'Rovedo', 1966),
('5308662562028069', 'Lucio', 'Bozzetto', 1973),
('5709182746975950', 'Luca', 'Spago', 1982),
('2952221988975144', 'Diego', 'Passoni', 1974),
('3660639182795303', 'Daniele', 'Zanchetta', 1965),
('6347910682766202', 'Daniela', 'Zanchettin', 1987),
('5610588346874144', 'Damir', 'Renko', 1977),
('4899373999221028', 'Daniel', 'Zago', 1989),
('1476135058642182', 'Damiano', 'Zanier', 1987),
('2350370609843529', 'Donatella', 'Zago', 1966),
('9602254547923502', 'Donato', 'Corsini', 1967),
('9737870513341704', 'Matteo', 'Sguazzero', 1997),
('8479625029717138', 'Mattias', 'Squaiera', 1965),
('8779321436104482', 'Mattia', 'Sordi', 1977),
('1277242508703705', 'Mattia', 'Sordon', 1958),
('3376454440879312', 'Mariella', 'Sordino', 1944),
('5908715410892026', 'Mariuccia', 'Sordi', 1935),
('1223257734355242', 'Federica', 'Sassari', 1986),
('8513625117329335', 'Maria', 'Sondrio', 1978),
('8881341362398211', 'Federico', 'Ramirez', 1977),
('2386308819452594', 'Felice', 'Savino', 1940),
('7058338154384458', 'Fulvio', 'Barletta', 1986),
('3270050952015192', 'Fausto', 'Tomasella', 1976),
('9356496113669188', 'Leonardo', 'Canzian', 1988),
('2848390064754011', 'Leonardo', 'Capraro', 1968),
('8135217333851993', 'Leo', 'Capri', 1989),
('8886702132777492', 'Leandro', 'Cancian', 1984),
('9322237861512694', 'Lisa', 'Marcon', 1944),
('3887234912853970', 'Riccardo', 'Bonanni', 1990),
('9331319079059548', 'Luca', 'Carsaniga', 1991),
('2352090747657245', 'Luca', 'Flaibani', 1988),
('6700249021503020', 'Gianluca', 'Pizzo', 1982),
('4627955477656729', 'Andrea', 'Largura', 1972),
('3717899578957511', 'Franceca', 'Romanutti', 1986),
('5398094289791378', 'Alina', 'Kovac', 1989),
('1755674318313148', 'Giulia', 'Slipcenco', 1985),
('8391708235326407', 'Harry', 'Leeroy', 1963),
('9483425052447368', 'Romeo', 'Pittolo', 1988),
('8155798923235291', 'Gabriele', 'Vanin', 1981),
('1936666089886054', 'Ilaria', 'Cancia', 1984),
('5487064388113717', 'Rita', 'Vidossi', 1964),
('3921585487645661', 'Gianna', 'Ziani', 1982),
('9037490306141074', 'Gianmatteo', 'Loiacono', 2000),
('9755999412118904', 'Riccardo', 'Roma', 1968),--da qua incluso sono pazienti passati
('3138900951277155', 'Clara', 'Romani', 1968),
('4974186081642257', 'Clarissa', 'Renzo', 1989),
('5305772417244601', 'Renzo', 'Canciani', 1959),
('4039104172645199', 'Claudia', 'Roman', 1979),
('4357643967478327', 'Claudio', 'Mengi', 1977),
('7722850787856033', 'David', 'Furlan', 1990),
('1207604900911223', 'Davide', 'Lucchetta', 1979),
('5444742150890779', 'Danny', 'Zucco', 1980),
('8353266679776440', 'Giorgio', 'Dorigo', 1975),
('5196514691498907', 'Giorgia', 'Mian', 1989),
('3359285313755286', 'Giovanni', 'Nadal', 1939),
('5975492463730331', 'Luciano', 'Grigio', 1934),
('9029553826233824', 'Emily', 'Bolton', 1964),
('5510508830062847', 'Agostino', 'Colombo', 1940),
('6723386800586444', 'Amedeo', 'Pitti', 1941),
('4295873975264389', 'Cesare', 'Ronchi', 1945),
('9730293485335770', 'Ciro', 'Rizzo', 1946),
('6876886547261205', 'Renato', 'Costa', 1970),
('9515544710920846', 'Giordano', 'De Luca', 1950);




INSERT INTO specializzazione (nome) VALUES
('Medicina interna'),
('Medicina d’emergenza-urgenza'),
('Geriatria'),
('Oncologia'),
('Pediatria'),
('Ematologia'),
('Neurologia'),
('Ginecologia ed ostetricia'),
('Psiachiatria'),
('Neuropsiachiatria infantile'),
('Nefrologia'),
('Anestesia'),
('Psiachiatria'),
('Cardiologia'),
('Urologia'),
('Chirurgia generale'),
('Chirurgia maxillo-facciale'),
('Chirurgia plastica, ricostruttiva ed estetica'),
('Neurochirurgia'),
('Chirurgia toracica'),
('Cardiochirurgia'),
('Ortopedia'),
('Otorinolaringoiatria'),
('Oftalmologia'),
('Chirurgia pediatrica'),
('Chirurgia vascolare'),
('Malattie infettive e tropicali'),
('Scienza dell’alimentazione'),
('Gastroenterologia'),
('Allergologia ed Immunologia clinica'),
('Dermatologia e Venereologia');



INSERT INTO reparto (nome, edificio, piano, letti_disponibili, letti_occupati, primario, data_inizio) VALUES
('Oncologia', 1, 3, 25, 0, '1846685306030041', '2015-04-06'),
('Chirurgia', 1, 2, 25, 0, '2846065032302035', '2018-05-02'),
('Pronto Soccorso', 1, 1, 15, 0, '5370097283258201', '2015-04-06'),
('Geriatria', 1, 3, 15, 0, '5856455334849193', '2016-05-29'),
('Ginecologia', 2, 3, 20, 0, '2219722864301108', '2017-05-29'),
('Pediatria', 2, 3, 20, 0, '7222181464671416', '2019-01-10'),
('Urologia', 2, 1, 20, 0, '6182593637417854', '2018-03-29'),
('Cardiologia', 2, 1, 20, 0, '4972751419368561', '2017-10-10'),
('Gastroenterologia', 2, 2, 20, 0, '8823711966847212', '2018-09-01'),
('Ortopedia', 2, 2, 20, 0, '5064900651193446', '2017-12-01');

INSERT INTO afferisce (medico, reparto) VALUES
('0000000000000000', 'Oncologia',
('0000000000000001', 'Oncologia'),
('0000000000000002', 'Oncologia'),
('1390252630529852', 'Chirurgia'),
('5397339808043402', 'Chirurgia'),
('8983816935854044', 'Chirurgia'),
('1846685306030041', 'Oncologia'),
('3359386196812767', 'Pronto Soccorso'),
('8229483796548314', 'Geriatria'),
('9986551251591601', 'Ginecologia'),
('9986551251591602', 'Ginecologia'),
('6270315354617646', 'Pediatria'),
('9532264530953180', 'Urologia'),
('9722043314326266', 'Cardiologia'),
('5247566716900138', 'Cardiologia'),
('1846344461747046', 'Gastroenterologia'),
('5064900651193446', 'Ortopedia'),
('3870666939878725', 'Gastroenterologia'),
('7612457177395462', 'Cardiologia'),
('8823711966847212', 'Gastroenterologia'),
('4972751419368561', 'Cardiologia'),
('4453712641026329', 'Ortopedia'),
('2846065032302035', 'Chirurgia'),
('7477983483987465', 'Pronto Soccorso'),
('6427536181858392', 'Urologia'),
('1069677691745915', 'Pediatria'),
('7517724820974182', 'Chirurgia'),
('6182593637417854', 'Urologia'),
('5370097283258201', 'Pronto Soccorso'),
('5856455334849193', 'Geriatria'),
('2219722864301108', 'Ginecologia'),
('7222181464671416', 'Pediatria')

INSERT INTO camera (id, reparto) VALUES
('A', 'Oncologia'),
('B', 'Oncologia'),
('C', 'Oncologia'),
('D', 'Oncologia'),
('A', 'Chirurgia'),
('B', 'Chirurgia'),
('C', 'Chirurgia'),
('D', 'Chirurgia'),
('E', 'Chirurgia'),
('F', 'Chirurgia'),
('G', 'Chirurgia'),
('A', 'Pronto Soccorso'),
('B', 'Pronto Soccorso'),
('C', 'Pronto Soccorso'),
('A', 'Geriatria'),
('B', 'Geriatria'),
('C', 'Geriatria'),
('A', 'Ginecologia'),
('B', 'Ginecologia'),
('C', 'Ginecologia'),
('D', 'Ginecologia'),
('A', 'Pediatria'),
('B', 'Pediatria'),
('C', 'Pediatria'),
('D', 'Pediatria'),
('A', 'Urologia'),
('B', 'Urologia'),
('C', 'Urologia'),
('A', 'Cardiologia'),
('B', 'Cardiologia'),
('C', 'Cardiologia'),
('D', 'Cardiologia'),
('A', 'Gastroenterologia'),
('B', 'Gastroenterologia'),
('C', 'Gastroenterologia'),
('D', 'Gastroenterologia'),
('A', 'Ortopedia'),
('B', 'Ortopedia'),
('C', 'Ortopedia'),
('D', 'Ortopedia');


INSERT INTO letto (id, reparto) VALUES
(1, 'Oncologia'),
(2, 'Oncologia'),
(3, 'Oncologia'),
(4, 'Oncologia'),
(5, 'Oncologia'),
(6, 'Oncologia'),
(7, 'Oncologia'),
(8, 'Oncologia'),
(9, 'Oncologia'),
(10, 'Oncologia'),
(11, 'Oncologia'),
(12, 'Oncologia'),
(13, 'Oncologia'),
(14, 'Oncologia'),
(15, 'Oncologia'),
(16, 'Oncologia'),
(17, 'Oncologia'),
(18, 'Oncologia'),
(19, 'Oncologia'),
(20, 'Oncologia'),
(21, 'Oncologia'),
(22, 'Oncologia'),
(23, 'Oncologia'),
(24, 'Oncologia'),
(25, 'Oncologia'),
(1, 'Chirurgia'),
(2, 'Chirurgia'),
(3, 'Chirurgia'),
(4, 'Chirurgia'),
(5, 'Chirurgia'),
(6, 'Chirurgia'),
(7, 'Chirurgia'),
(8, 'Chirurgia'),
(9, 'Chirurgia'),
(10, 'Chirurgia'),
(11, 'Chirurgia'),
(12, 'Chirurgia'),
(13, 'Chirurgia'),
(14, 'Chirurgia'),
(15, 'Chirurgia'),
(16, 'Chirurgia'),
(17, 'Chirurgia'),
(18, 'Chirurgia'),
(19, 'Chirurgia'),
(20, 'Chirurgia'),
(21, 'Chirurgia'),
(22, 'Chirurgia'),
(23, 'Chirurgia'),
(24, 'Chirurgia'),
(25, 'Chirurgia'),
(1, 'Pronto Soccorso'),
(2, 'Pronto Soccorso'),
(3, 'Pronto Soccorso'),
(4, 'Pronto Soccorso'),
(5, 'Pronto Soccorso'),
(6, 'Pronto Soccorso'),
(7, 'Pronto Soccorso'),
(8, 'Pronto Soccorso'),
(9, 'Pronto Soccorso'),
(10, 'Pronto Soccorso'),
(11, 'Pronto Soccorso'),
(12, 'Pronto Soccorso'),
(13, 'Pronto Soccorso'),
(14, 'Pronto Soccorso'),
(15, 'Pronto Soccorso'),
(1, 'Geriatria'),
(2, 'Geriatria'),
(3, 'Geriatria'),
(4, 'Geriatria'),
(5, 'Geriatria'),
(6, 'Geriatria'),
(7, 'Geriatria'),
(8, 'Geriatria'),
(9, 'Geriatria'),
(10, 'Geriatria'),
(11, 'Geriatria'),
(12, 'Geriatria'),
(13, 'Geriatria'),
(14, 'Geriatria'),
(15, 'Geriatria'),
(1, 'Ginecologia'),
(2, 'Ginecologia'),
(3, 'Ginecologia'),
(4, 'Ginecologia'),
(5, 'Ginecologia'),
(6, 'Ginecologia'),
(7, 'Ginecologia'),
(8, 'Ginecologia'),
(9, 'Ginecologia'),
(10, 'Ginecologia'),
(11, 'Ginecologia'),
(12, 'Ginecologia'),
(13, 'Ginecologia'),
(14, 'Ginecologia'),
(15, 'Ginecologia'),
(16, 'Ginecologia'),
(17, 'Ginecologia'),
(18, 'Ginecologia'),
(19, 'Ginecologia'),
(20, 'Ginecologia'),
(1, 'Pediatria'),
(2, 'Pediatria'),
(3, 'Pediatria'),
(4, 'Pediatria'),
(5, 'Pediatria'),
(6, 'Pediatria'),
(7, 'Pediatria'),
(8, 'Pediatria'),
(9, 'Pediatria'),
(10, 'Pediatria'),
(11, 'Pediatria'),
(12, 'Pediatria'),
(13, 'Pediatria'),
(14, 'Pediatria'),
(15, 'Pediatria'),
(16, 'Pediatria'),
(17, 'Pediatria'),
(18, 'Pediatria'),
(19, 'Pediatria'),
(20, 'Pediatria'),
(1, 'Urologia'),
(2, 'Urologia'),
(3, 'Urologia'),
(4, 'Urologia'),
(5, 'Urologia'),
(6, 'Urologia'),
(7, 'Urologia'),
(8, 'Urologia'),
(9, 'Urologia'),
(10, 'Urologia'),
(11, 'Urologia'),
(12, 'Urologia'),
(13, 'Urologia'),
(14, 'Urologia'),
(15, 'Urologia'),
(16, 'Urologia'),
(17, 'Urologia'),
(18, 'Urologia'),
(19, 'Urologia'),
(20, 'Urologia'),
(1, 'Cardiologia'),
(2, 'Cardiologia'),
(3, 'Cardiologia'),
(4, 'Cardiologia'),
(5, 'Cardiologia'),
(6, 'Cardiologia'),
(7, 'Cardiologia'),
(8, 'Cardiologia'),
(9, 'Cardiologia'),
(10, 'Cardiologia'),
(11, 'Cardiologia'),
(12, 'Cardiologia'),
(13, 'Cardiologia'),
(14, 'Cardiologia'),
(15, 'Cardiologia'),
(16, 'Cardiologia'),
(17, 'Cardiologia'),
(18, 'Cardiologia'),
(19, 'Cardiologia'),
(20, 'Cardiologia'),
(1, 'Gastroenterologia'),
(2, 'Gastroenterologia'),
(3, 'Gastroenterologia'),
(4, 'Gastroenterologia'),
(5, 'Gastroenterologia'),
(6, 'Gastroenterologia'),
(7, 'Gastroenterologia'),
(8, 'Gastroenterologia'),
(9, 'Gastroenterologia'),
(10, 'Gastroenterologia'),
(11, 'Gastroenterologia'),
(12, 'Gastroenterologia'),
(13, 'Gastroenterologia'),
(14, 'Gastroenterologia'),
(15, 'Gastroenterologia'),
(16, 'Gastroenterologia'),
(17, 'Gastroenterologia'),
(18, 'Gastroenterologia'),
(19, 'Gastroenterologia'),
(20, 'Gastroenterologia'),
(1, 'Ortopedia'),
(2, 'Ortopedia'),
(3, 'Ortopedia'),
(4, 'Ortopedia'),
(5, 'Ortopedia'),
(6, 'Ortopedia'),
(7, 'Ortopedia'),
(8, 'Ortopedia'),
(9, 'Ortopedia'),
(10, 'Ortopedia'),
(11, 'Ortopedia'),
(12, 'Ortopedia'),
(13, 'Ortopedia'),
(14, 'Ortopedia'),
(15, 'Ortopedia'),
(16, 'Ortopedia'),
(17, 'Ortopedia'),
(18, 'Ortopedia'),
(19, 'Ortopedia'),
(20, 'Ortopedia');

INSERT INTO si_trova (id_letto, reparto, id_camera) VALUES
(1, 'Oncologia', 'A'),
(2, 'Oncologia', 'A'),
(3, 'Oncologia', 'A'),
(4, 'Oncologia', 'A'),
(5, 'Oncologia', 'A'),
(6, 'Oncologia', 'A'),
(7, 'Oncologia', 'A'),
(8, 'Oncologia', 'A'),
(9, 'Oncologia', 'B'),
(10, 'Oncologia', 'B'),
(11, 'Oncologia', 'B'),
(12, 'Oncologia', 'B'),
(13, 'Oncologia', 'B'),
(14, 'Oncologia', 'C'),
(15, 'Oncologia', 'C'),
(16, 'Oncologia', 'C'),
(17, 'Oncologia', 'C'),
(18, 'Oncologia', 'D'),
(19, 'Oncologia', 'D'),
(20, 'Oncologia', 'D'),
(21, 'Oncologia', 'D'),
(22, 'Oncologia', 'D'),
(23, 'Oncologia', 'D'),
(24, 'Oncologia', 'D'),
(25, 'Oncologia', 'D'),
(1, 'Chirurgia', 'A'),
(2, 'Chirurgia', 'A'),
(3, 'Chirurgia', 'A'),
(4, 'Chirurgia', 'A'),
(5, 'Chirurgia', 'B'),
(6, 'Chirurgia', 'B'),
(7, 'Chirurgia', 'C'),
(8, 'Chirurgia', 'C'),
(9, 'Chirurgia', 'C'),
(10, 'Chirurgia', 'C'),
(11, 'Chirurgia', 'C'),
(12, 'Chirurgia', 'D'),
(13, 'Chirurgia', 'D'),
(14, 'Chirurgia', 'D'),
(15, 'Chirurgia', 'D'),
(16, 'Chirurgia', 'E'),
(17, 'Chirurgia', 'E'),
(18, 'Chirurgia', 'E'),
(19, 'Chirurgia', 'E'),
(20, 'Chirurgia', 'E'),
(21, 'Chirurgia', 'E'),
(22, 'Chirurgia', 'F'),
(23, 'Chirurgia', 'F'),
(24, 'Chirurgia', 'G'),
(25, 'Chirurgia', 'G'),
(1, 'Pronto Soccorso', 'A'),
(2, 'Pronto Soccorso', 'A'),
(3, 'Pronto Soccorso', 'A'),
(4, 'Pronto Soccorso', 'A'),
(5, 'Pronto Soccorso', 'A'),
(6, 'Pronto Soccorso', 'A'),
(7, 'Pronto Soccorso', 'A'),
(8, 'Pronto Soccorso', 'B'),
(9, 'Pronto Soccorso', 'B'),
(10, 'Pronto Soccorso', 'B'),
(11, 'Pronto Soccorso', 'B'),
(12, 'Pronto Soccorso', 'B'),
(13, 'Pronto Soccorso', 'C'),
(14, 'Pronto Soccorso', 'C'),
(15, 'Pronto Soccorso', 'C'),
(1, 'Geriatria', 'A'),
(2, 'Geriatria', 'A'),
(3, 'Geriatria', 'A'),
(4, 'Geriatria', 'A'),
(5, 'Geriatria', 'B'),
(6, 'Geriatria', 'B'),
(7, 'Geriatria', 'B'),
(8, 'Geriatria', 'B'),
(9, 'Geriatria', 'B'),
(10, 'Geriatria', 'C'),
(11, 'Geriatria', 'C'),
(12, 'Geriatria', 'C'),
(13, 'Geriatria', 'C'),
(14, 'Geriatria', 'C'),
(15, 'Geriatria', 'C'),
(1, 'Ginecologia', 'A'),
(2, 'Ginecologia', 'A'),
(3, 'Ginecologia', 'A'),
(4, 'Ginecologia', 'A'),
(5, 'Ginecologia', 'A'),
(6, 'Ginecologia', 'A'),
(7, 'Ginecologia', 'B'),
(8, 'Ginecologia', 'B'),
(9, 'Ginecologia', 'B'),
(10, 'Ginecologia', 'B'),
(11, 'Ginecologia', 'B'),
(12, 'Ginecologia', 'B'),
(13, 'Ginecologia', 'C'),
(14, 'Ginecologia', 'C'),
(15, 'Ginecologia', 'C'),
(16, 'Ginecologia', 'C'),
(17, 'Ginecologia', 'C'),
(18, 'Ginecologia', 'D'),
(19, 'Ginecologia', 'D'),
(20, 'Ginecologia', 'D'),
(1, 'Pediatria', 'A'),
(2, 'Pediatria', 'A'),
(3, 'Pediatria', 'A'),
(4, 'Pediatria', 'A'),
(5, 'Pediatria', 'A'),
(6, 'Pediatria', 'B'),
(7, 'Pediatria', 'B'),
(8, 'Pediatria', 'B'),
(9, 'Pediatria', 'B'),
(10, 'Pediatria', 'B'),
(11, 'Pediatria', 'B'),
(12, 'Pediatria', 'B'),
(13, 'Pediatria', 'B'),
(14, 'Pediatria', 'C'),
(15, 'Pediatria', 'C'),
(16, 'Pediatria', 'D'),
(17, 'Pediatria', 'D'),
(18, 'Pediatria', 'D'),
(19, 'Pediatria', 'D'),
(20, 'Pediatria', 'D'),
(1, 'Urologia', 'A'),
(2, 'Urologia', 'A'),
(3, 'Urologia', 'A'),
(4, 'Urologia', 'A'),
(5, 'Urologia', 'A'),
(6, 'Urologia', 'A'),
(7, 'Urologia', 'A'),
(8, 'Urologia', 'A'),
(9, 'Urologia', 'B'),
(10, 'Urologia', 'B'),
(11, 'Urologia', 'B'),
(12, 'Urologia', 'B'),
(13, 'Urologia', 'B'),
(14, 'Urologia', 'B'),
(15, 'Urologia', 'B'),
(16, 'Urologia', 'B'),
(17, 'Urologia', 'C'),
(18, 'Urologia', 'C'),
(19, 'Urologia', 'C'),
(20, 'Urologia', 'C'),
(1, 'Cardiologia', 'A'),
(2, 'Cardiologia', 'A'),
(3, 'Cardiologia', 'A'),
(4, 'Cardiologia', 'A'),
(5, 'Cardiologia', 'A'),
(6, 'Cardiologia', 'B'),
(7, 'Cardiologia', 'B'),
(8, 'Cardiologia', 'B'),
(9, 'Cardiologia', 'B'),
(10, 'Cardiologia', 'B'),
(11, 'Cardiologia', 'B'),
(12, 'Cardiologia', 'C'),
(13, 'Cardiologia', 'C'),
(14, 'Cardiologia', 'C'),
(15, 'Cardiologia', 'C'),
(16, 'Cardiologia', 'D'),
(17, 'Cardiologia', 'D'),
(18, 'Cardiologia', 'D'),
(19, 'Cardiologia', 'D'),
(20, 'Cardiologia', 'D'),
(1, 'Gastroenterologia', 'A'),
(2, 'Gastroenterologia', 'A'),
(3, 'Gastroenterologia', 'A'),
(4, 'Gastroenterologia', 'A'),
(5, 'Gastroenterologia', 'A'),
(6, 'Gastroenterologia', 'A'),
(7, 'Gastroenterologia', 'B'),
(8, 'Gastroenterologia', 'B'),
(9, 'Gastroenterologia', 'B'),
(10, 'Gastroenterologia', 'B'),
(11, 'Gastroenterologia', 'B'),
(12, 'Gastroenterologia', 'B'),
(13, 'Gastroenterologia', 'C'),
(14, 'Gastroenterologia', 'C'),
(15, 'Gastroenterologia', 'C'),
(16, 'Gastroenterologia', 'C'),
(17, 'Gastroenterologia', 'C'),
(18, 'Gastroenterologia', 'C'),
(19, 'Gastroenterologia', 'D'),
(20, 'Gastroenterologia', 'D'),
(1, 'Ortopedia', 'A'),
(2, 'Ortopedia', 'A'),
(3, 'Ortopedia', 'A'),
(4, 'Ortopedia', 'A'),
(5, 'Ortopedia', 'A'),
(6, 'Ortopedia', 'A'),
(7, 'Ortopedia', 'A'),
(8, 'Ortopedia', 'B'),
(9, 'Ortopedia', 'B'),
(10, 'Ortopedia', 'B'),
(11, 'Ortopedia', 'B'),
(12, 'Ortopedia', 'B'),
(13, 'Ortopedia', 'B'),
(14, 'Ortopedia', 'B'),
(15, 'Ortopedia', 'C'),
(16, 'Ortopedia', 'C'),
(17, 'Ortopedia', 'C'),
(18, 'Ortopedia', 'D'),
(19, 'Ortopedia', 'D'),
(20, 'Ortopedia', 'D');

INSERT INTO occupa_attualmente (paziente, id_letto, reparto, data_ricovero) VALUES
('0000000000000000', 1, 'Pronto Soccorso', '2019-08-20'),
('0000000000000001', 2, 'Pronto Soccorso', '2019-08-25'),
('0000000000000002', 3, 'Pronto Soccorso', '2019-08-24'),
('8225751935680501', 4, 'Pronto Soccorso', '2019-08-19'),
('4224355445461313', 5, 'Pronto Soccorso', '2019-08-21'),
('6337027164120347', 6, 'Pronto Soccorso', '2019-08-22'),
('7331442932981994', 7, 'Pronto Soccorso', '2019-08-22'),
('1868936191486718', 8, 'Pronto Soccorso', '2019-08-23'),
('6814449000846526', 9, 'Pronto Soccorso', '2019-08-24'),
('4077100134185992', 10, 'Pronto Soccorso', '2019-08-25'),
('8010657258419520', 11, 'Pronto Soccorso', '2019-08-25'),
('4418933657981244', 1, 'Oncologia', '2019-07-30'),
('6627897026222284', 2, 'Oncologia', '2019-08-01'),
('6438139634395960', 3, 'Oncologia', '2019-06-20'),
('7653062108131006', 4, 'Oncologia', '2019-08-22'),
('5588574605730229', 5, 'Oncologia', '2019-07-14'),
('2720222047038703', 6, 'Oncologia', '2019-07-17'),
('5627971602753923', 7, 'Oncologia', '2019-06-11'),
('8346800316953369', 8, 'Oncologia', '2019-08-21'),
('9337383323309168', 9, 'Oncologia', '2019-08-12'),
('9410825649373196', 1, 'Pediatria', '2019-07-25'),
('7096793081288325', 2, 'Pediatria', '2019-08-05'),
('8524011104695532', 3, 'Pediatria', '2019-08-03'),
('8936419229711070', 4, 'Pediatria', '2019-07-19'),
('9735563994270860', 5, 'Pediatria', '2019-08-04'),
('3170891874979344', 6, 'Pediatria', '2019-08-02'),
('9274115114979232', 7, 'Pediatria', '2019-08-10'),
('1308368971707572', 1, 'Urologia', '2019-08-11'),
('7101809454382081', 2, 'Urologia', '2019-08-27'),
('5701623795430872', 3, 'Urologia', '2019-07-28'),
('6506917832305512', 1, 'Chirurgia', '2019-08-20'),
('6883649214252943', 2, 'Chirurgia', '2019-08-14'),
('1359567119628313', 3, 'Chirurgia', '2019-08-10'),
('6556042443923494', 4, 'Chirurgia', '2019-08-22'),
('8965488863765894', 5, 'Chirurgia', '2019-08-11'),
('7730531723964112', 6, 'Chirurgia', '2019-08-02'),
('1979758501449854', 7, 'Chirurgia', '2019-07-30'),
('3183465973212040', 8, 'Chirurgia', '2019-08-05'),
('5308662562028069', 9, 'Chirurgia', '2019-08-23'),
('5709182746975950', 1, 'Geriatria', '2019-08-20'),
('2952221988975144', 2, 'Geriatria', '2019-08-19'),
('3660639182795303', 3, 'Geriatria', '2019-08-15'),
('6347910682766202', 4, 'Geriatria', '2019-08-17'),
('5610588346874144', 5, 'Geriatria', '2019-07-30'),
('4899373999221028', 6, 'Geriatria', '2019-08-10'),
('1476135058642182', 7, 'Geriatria', '2019-08-11'),
('2350370609843529', 8, 'Geriatria', '2019-08-12'),
('9602254547923502', 9, 'Geriatria', '2019-08-17'),
('9737870513341704', 10, 'Geriatria', '2019-07-29'),
('8479625029717138', 11, 'Geriatria', '2019-08-15'),
('8779321436104482', 12, 'Geriatria', '2019-08-19'),
('1277242508703705', 13, 'Geriatria', '2019-08-16'),
('3376454440879312', 14, 'Geriatria', '2019-08-14'),
('5908715410892026', 15, 'Geriatria', '2019-08-05'),
('1223257734355242', 1, 'Ginecologia', '2019-08-24'),
('8513625117329335', 2, 'Ginecologia', '2019-08-22'),
('8881341362398211', 1, 'Cardiologia', '2019-08-21'),
('2386308819452594', 2, 'Cardiologia', '2019-08-14'),
('7058338154384458', 3, 'Cardiologia', '2019-08-12'),
('3270050952015192', 4, 'Cardiologia', '2019-08-18'),
('9356496113669188', 1, 'Gastroenterologia', '2019-08-05'),
('2848390064754011', 2, 'Gastroenterologia', '2019-08-14'),
('8135217333851993', 3, 'Gastroenterologia', '2019-08-23'),
('8886702132777492', 4, 'Gastroenterologia', '2019-08-10'),
('9322237861512694', 3, 'Ginecologia', '2019-08-21'),
('3887234912853970', 1, 'Ortopedia', '2019-08-25'),
('9331319079059548', 2, 'Ortopedia', '2019-08-19'),
('2352090747657245', 3, 'Ortopedia', '2019-08-24'),
('6700249021503020', 4, 'Ortopedia', '2019-08-22'),
('4627955477656729', 5, 'Ortopedia', '2019-08-21'),
('3717899578957511', 4, 'Ginecologia', '2019-08-20'),
('5398094289791378', 5, 'Ginecologia', '2019-08-21'),
('1755674318313148', 6, 'Ginecologia', '2019-08-24'),
('8391708235326407', 7, 'Ortopedia', '2019-08-20'),
('9483425052447368', 8, 'Ortopedia', '2019-08-22'),
('8155798923235291', 9, 'Ortopedia', '2019-08-21'),
('1936666089886054', 7, 'Ginecologia', '2019-08-19'),
('5487064388113717', 8, 'Ginecologia', '2019-08-25'),
('3921585487645661', 10, 'Ortopedia', '2019-08-29'),
('9037490306141074', 11, 'Ortopedia', '2019-08-21');

INSERT INTO ricovero_passato (paziente, data_ricovero, data_dimissioni, letto, reparto) VALUES
('9755999412118904', '2019-05-25', '2019-05-27', 4, 'Oncologia'),
('3138900951277155', '2019-06-15', '2019-06-25', 7, 'Cardiologia'),
('4974186081642257', '2019-04-10', '2019-04-10', 5, 'Pronto Soccorso'),
('5305772417244601', '2019-02-21', '2019-02-25', 10, 'Ortopedia'),
('4039104172645199', '2019-03-21', '2019-03-22', 12, 'Pronto Soccorso'),
('4357643967478327', '2019-07-06', '2019-07-12', 20, 'Chirurgia'),
('7722850787856033', '2019-06-09', '2019-07-15', 14, 'Oncologia'),
('1207604900911223', '2019-08-01', '2019-08-05', 9, 'Gastroenterologia'),
('5444742150890779', '2019-01-25', '2019-02-01', 13, 'Urologia'),
('8353266679776440', '2019-02-10', '2019-02-13', 5, 'Pronto Soccorso'),
('5196514691498907', '2019-05-15', '2019-05-18', 6, 'Ginecologia'),
('3359285313755286', '2019-06-26', '2019-06-29', 3, 'Geriatria'),
('5975492463730331', '2019-07-07', '2019-07-10', 15, 'Chirurgia'),
('9029553826233824', '2019-06-05', '2019-06-11', 1 , 'Cardiologia'),
('5510508830062847', '2019-03-20', '2019-04-15', 9, 'Oncologia'),
('6723386800586444', '2019-05-17', '2019-05-20', 12, 'Chirurgia'),
('4295873975264389', '2019-06-20', '2019-06-24', 4, 'Urologia'),
('9730293485335770', '2019-06-15', '2019-06-20', 3, 'Chirurgia'),
('6876886547261205', '2019-07-01', '2019-07-02', 6, 'Chirurgia'),
('9515544710920846', '2019-05-15', '2019-05-17', 9, 'Chirurgia'),
('5398094289791378', '2019-01-25', '2019-01-30', 2, 'Ginecologia'),
('1359567119628313', '2019-01-09', '2019-01-14', 4, 'Chirurgia'),
('8886702132777492', '2019-02-21', '2019-02-25', 8, 'Gastroenterologia'),
('6347910682766202', '2019-04-23', '2019-04-25', 7, 'Geriatria');
--chirurgia ok
--oncologia ok
--pronto soccorso ok
--geriatria ok
--ginecologia ok
--pediatria ok
--cardiologia ok
--ortopedia ok
--gastroentereologia ok
--urologia ok

INSERT INTO diagnosi (medico, paziente, descrizione) VALUES
('0000000000000000', '7722850787856033', null),
('0000000000000001', '9755999412118904', null),
('1390252630529852', '4357643967478327', null),
('1390252630529852', '6723386800586444', null),
('5397339808043402', '5975492463730331', null),
('5397339808043402', '9730293485335770', null),
('8983816935854044', '6876886547261205', null),
('5397339808043402', '6876886547261205', null),
('5397339808043402', '1359567119628313', null),
('1846685306030041', '5510508830062847', null),
('3359386196812767', '4974186081642257', null),
('8229483796548314', '3359285313755286', null),
('9986551251591601', '5196514691498907', null),
('9986551251591601', '5398094289791378', null),
('6270315354617646', '8524011104695532', null),
('9532264530953180', '5444742150890779', null),
('9722043314326266', '3138900951277155', null),
('5247566716900138', '9029553826233824', null),
('1846344461747046', '1207604900911223', null),
('5064900651193446', '5305772417244601', null),
('3870666939878725', '8886702132777492', null),
('8823711966847212', '8135217333851993', null),
('4972751419368561', '8881341362398211', null),
('4453712641026329', '2352090747657245', null),
('4453712641026329', '4627955477656729', null),
('2846065032302035', '1359567119628313', null),
('7477983483987465', '4039104172645199', null),
('6427536181858392', '4295873975264389', null),
('1069677691745915', '3170891874979344', null),
('7517724820974182', '7730531723964112', null),
('6182593637417854', '1308368971707572', null),
('5370097283258201', '8353266679776440', null),
('5856455334849193', '6347910682766202', null),
('2219722864301108', '1223257734355242', null),
('7222181464671416', '9274115114979232', null);

INSERT INTO ha_ottenuto (medico, specializzazione) VALUES
('0000000000000000', 'Ortopedia'),
('0000000000000000', 'Oncologia'),
('0000000000000001', 'Medicina interna'),
('0000000000000001', 'Oncologia'),
('0000000000000002', 'Medicina d’emergenza-urgenza'),
('1390252630529852', 'Geriatria'),
('1390252630529852', 'Chirurgia generale'),
('5397339808043402', 'Oncologia'),
('5397339808043402', 'Chirurgia plastica, ricostruttiva ed estetica'),
('8983816935854044', 'Pediatria'),
('8983816935854044', 'Chirurgia maxillo-facciale'),
('1846685306030041', 'Oncologia'),
('3359386196812767', 'Ginecologia ed ostetricia'),
('8229483796548314', 'Geriatria'),
('9986551251591601', 'Ginecologia ed ostetricia'),
('9986551251591602', 'Medicina d’emergenza-urgenza'),
('9986551251591602', 'Gastroenterologia'),
('9986551251591602', 'Ginecologia'),
('6270315354617646', 'Chirurgia plastica, ricostruttiva ed estetica'),
('6270315354617646', 'Chirurgia maxillo-facciale'),
('9532264530953180', 'Gastroenterologia'),
('9532264530953180', 'Urologia'),
('9722043314326266', 'Cadiologia'),
('5247566716900138', 'Pediatria'),
('5247566716900138', 'Cardiologia'),
('1846344461747046', 'Ginecologia ed ostetricia'),
('1846344461747046', 'Pediatria'),
('5064900651193446', 'Ortopedia'),
('3870666939878725', 'Ginecologia ed ostetricia'),
('7612457177395462', 'Ginecologia ed ostetricia'),
('8823711966847212', 'Gastroenterologia'),
('4972751419368561', 'Cardiologia'),
('4453712641026329', 'Ortopedia'),
('2846065032302035', 'Chirurgia generale'),
('7477983483987465', 'Urologia'),
('6427536181858392', 'Urologia'),
('1069677691745915', 'Pediatria'),
('1069677691745915', 'Chirurgia generale'),
('7517724820974182', 'Chirurgia generale'),
('6182593637417854', 'Urologia'),
('5370097283258201', 'Medicina d’emergenza-urgenza'),
('5370097283258201', 'Ematologia'),
('5856455334849193', 'Geriatria'),
('2219722864301108', 'Ginecologia ed ostetricia'),
('7222181464671416', 'Pediatria');