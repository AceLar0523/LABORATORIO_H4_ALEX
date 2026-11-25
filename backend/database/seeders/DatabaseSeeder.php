<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\User;
use App\Models\Vehiculo;
use App\Models\Caseta;
use App\Models\Tarifa;
use App\Models\Paso;
use App\Models\Alerta;

class DatabaseSeeder extends Seeder
{
    /**
     * Seed the application's database.
     */
    public function run(): void
    {
        // 1. Usuarios con Google Email (Lista Blanca y Roles)
        User::updateOrCreate(
            ['email_google' => 'docente@peaje.edu'],
            ['nombre' => 'Docente Evaluador', 'rol' => 'administrador', 'activo' => true]
        );

        User::updateOrCreate(
            ['email_google' => 'admin@peaje.com'],
            ['nombre' => 'Administrador General', 'rol' => 'administrador', 'activo' => true]
        );

        User::updateOrCreate(
            ['email_google' => 'operador@peaje.com'],
            ['nombre' => 'Operador Caseta 1', 'rol' => 'operador', 'activo' => true]
        );

        // 2. Casetas
        $caseta1 = Caseta::firstOrCreate(['nombre' => 'Caseta Principal Norte'], ['ubicacion' => 'Autopista Km 15']);
        $caseta2 = Caseta::firstOrCreate(['nombre' => 'Caseta Sur - Vía Expresa'], ['ubicacion' => 'Autopista Km 42']);

        // 3. Tarifas (categoria, ejes, monto)
        $tarifasData = [
            ['categoria' => 'moto', 'ejes' => 2, 'monto' => 5.00],
            ['categoria' => 'auto', 'ejes' => 2, 'monto' => 10.00],
            ['categoria' => 'minibus', 'ejes' => 2, 'monto' => 15.00],
            ['categoria' => 'bus', 'ejes' => 2, 'monto' => 25.00],
            ['categoria' => 'bus', 'ejes' => 3, 'monto' => 30.00],
            ['categoria' => 'camion', 'ejes' => 2, 'monto' => 25.00],
            ['categoria' => 'camion', 'ejes' => 3, 'monto' => 35.00],
            ['categoria' => 'camion', 'ejes' => 4, 'monto' => 45.00],
            ['categoria' => 'camion', 'ejes' => 5, 'monto' => 60.00],
            ['categoria' => 'camion', 'ejes' => 6, 'monto' => 75.00],
            ['categoria' => 'trailer', 'ejes' => 4, 'monto' => 55.00],
            ['categoria' => 'trailer', 'ejes' => 5, 'monto' => 70.00],
            ['categoria' => 'trailer', 'ejes' => 6, 'monto' => 85.00],
        ];

        foreach ($tarifasData as $t) {
            Tarifa::updateOrCreate(
                ['categoria' => $t['categoria'], 'ejes' => $t['ejes']],
                ['monto' => $t['monto']]
            );
        }

        // 4. Mínimo 20 Vehículos de Prueba
        $vehiculos = [
            ['placa' => '4021XYZ', 'propietario' => 'Carlos Mendoza', 'categoria' => 'auto', 'ejes' => 2, 'saldo' => 120.00, 'activo' => true],
            ['placa' => '3142ABC', 'propietario' => 'Lucía Fernández', 'categoria' => 'auto', 'ejes' => 2, 'saldo' => 50.00, 'activo' => true],
            ['placa' => '2890LKJ', 'propietario' => 'Juan Pérez', 'categoria' => 'moto', 'ejes' => 2, 'saldo' => 30.00, 'activo' => true],
            ['placa' => '1540QWE', 'propietario' => 'Transportes Cóndor', 'categoria' => 'camion', 'ejes' => 3, 'saldo' => 250.00, 'activo' => true],
            ['placa' => '5012TYU', 'propietario' => 'Expreso del Valle', 'categoria' => 'bus', 'ejes' => 3, 'saldo' => 180.00, 'activo' => true],
            ['placa' => '1209OPL', 'propietario' => 'Marina Silva', 'categoria' => 'auto', 'ejes' => 2, 'saldo' => 0.00, 'activo' => true], // Sin saldo
            ['placa' => '7845MNB', 'propietario' => 'Roberto Gómez', 'categoria' => 'minibus', 'ejes' => 2, 'saldo' => 75.00, 'activo' => true],
            ['placa' => '6523ASD', 'propietario' => 'Distribuidora Los Andes', 'categoria' => 'camion', 'ejes' => 4, 'saldo' => 320.00, 'activo' => true],
            ['placa' => '9941FGH', 'propietario' => 'Elena Ríos', 'categoria' => 'auto', 'ejes' => 2, 'saldo' => 40.00, 'activo' => true],
            ['placa' => '1122JKL', 'propietario' => 'Fernando Castro', 'categoria' => 'moto', 'ejes' => 2, 'saldo' => 15.00, 'activo' => true],
            ['placa' => '3344ZXC', 'propietario' => 'Servicios Rápidos SRL', 'categoria' => 'minibus', 'ejes' => 2, 'saldo' => 90.00, 'activo' => true],
            ['placa' => '5566VBN', 'propietario' => 'Hugo Morales', 'categoria' => 'auto', 'ejes' => 2, 'saldo' => 100.00, 'activo' => true],
            ['placa' => '7788BNM', 'propietario' => 'Flota Imperial', 'categoria' => 'bus', 'ejes' => 2, 'saldo' => 0.00, 'activo' => true], // Sin saldo
            ['placa' => '9900QAZ', 'propietario' => 'Logística Global', 'categoria' => 'camion', 'ejes' => 5, 'saldo' => 500.00, 'activo' => true],
            ['placa' => '2233WSX', 'propietario' => 'Paola Vargas', 'categoria' => 'auto', 'ejes' => 2, 'saldo' => 60.00, 'activo' => true],
            ['placa' => '4455EDC', 'propietario' => 'Gabriel Romero', 'categoria' => 'auto', 'ejes' => 2, 'saldo' => 15.00, 'activo' => true],
            ['placa' => '6677RFV', 'propietario' => 'Transporte Pesado Sol', 'categoria' => 'camion', 'ejes' => 3, 'saldo' => 140.00, 'activo' => true],
            ['placa' => '8899TGB', 'propietario' => 'Camila Delgado', 'categoria' => 'minibus', 'ejes' => 2, 'saldo' => 45.00, 'activo' => true],
            ['placa' => '1357YHN', 'propietario' => 'Álvaro Tapia', 'categoria' => 'auto', 'ejes' => 2, 'saldo' => 80.00, 'activo' => true],
            ['placa' => '2468UJM', 'propietario' => 'Valeria Navarro', 'categoria' => 'auto', 'ejes' => 2, 'saldo' => 110.00, 'activo' => true],
            ['placa' => '3579IKL', 'propietario' => 'Cargas del Oriente', 'categoria' => 'camion', 'ejes' => 4, 'saldo' => 210.00, 'activo' => true],
        ];

        foreach ($vehiculos as $v) {
            Vehiculo::updateOrCreate(['placa' => $v['placa']], $v);
        }

        // 5. Sembrar un paso inicial de ejemplo con su alerta
        $userOp = User::where('email_google', 'operador@peaje.com')->first();
        $pasoEjemplo = Paso::firstOrCreate(
            ['placa_normalizada' => '4021XYZ'],
            [
                'placa_leida' => '4021-XYZ',
                'confianza_ocr' => 0.95,
                'categoria_detectada' => 'auto',
                'ejes_detectados' => 2,
                'monto' => 10.00,
                'caseta_id' => $caseta1->id,
                'usuario_id' => $userOp->id,
                'imagen_url' => null,
                'estado' => 'Registrada y con paso',
                'pasajeros' => 2,
            ]
        );

        // Paso con placa no registrada
        $pasoAlerta = Paso::firstOrCreate(
            ['placa_normalizada' => '9999INV'],
            [
                'placa_leida' => '9999-INV',
                'confianza_ocr' => 0.88,
                'categoria_detectada' => 'camion',
                'ejes_detectados' => 3,
                'monto' => 35.00,
                'caseta_id' => $caseta1->id,
                'usuario_id' => $userOp->id,
                'imagen_url' => null,
                'estado' => 'Identificada no registrada',
                'pasajeros' => 1,
            ]
        );

        Alerta::firstOrCreate(
            ['paso_id' => $pasoAlerta->id],
            [
                'tipo' => 'placa_no_registrada',
                'mensaje' => 'Vehículo 9999INV no registrado transitando por Caseta Principal Norte',
                'atendida' => false,
            ]
        );
    }
}
