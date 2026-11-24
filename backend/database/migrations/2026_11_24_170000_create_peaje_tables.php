<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // vehiculos(id, placa, propietario, categoria, ejes, saldo, activo)
        Schema::create('vehiculos', function (Blueprint $table) {
            $table->id();
            $table->string('placa', 15)->unique();
            $table->string('propietario');
            $table->string('categoria', 30); // auto, moto, minibus, camion, bus
            $table->integer('ejes')->default(2);
            $table->decimal('saldo', 10, 2)->default(0.00);
            $table->boolean('activo')->default(true);
            $table->timestamps();
        });

        // casetas(id, nombre, ubicacion)
        Schema::create('casetas', function (Blueprint $table) {
            $table->id();
            $table->string('nombre');
            $table->string('ubicacion');
            $table->timestamps();
        });

        // tarifas(categoria, ejes, monto)
        Schema::create('tarifas', function (Blueprint $table) {
            $table->id();
            $table->string('categoria', 30);
            $table->integer('ejes')->default(2);
            $table->decimal('monto', 10, 2);
            $table->timestamps();
            $table->unique(['categoria', 'ejes']);
        });

        // pasos(id, placa_leida, placa_normalizada, confianza_ocr, categoria_detectada, ejes_detectados, monto, caseta_id, usuario_id, imagen_url, estado, created_at)
        Schema::create('pasos', function (Blueprint $table) {
            $table->id();
            $table->string('placa_leida', 30)->nullable();
            $table->string('placa_normalizada', 30)->nullable();
            $table->decimal('confianza_ocr', 5, 2)->default(0.00);
            $table->string('categoria_detectada', 30)->nullable();
            $table->integer('ejes_detectados')->default(2);
            $table->decimal('monto', 10, 2)->default(0.00);
            $table->foreignId('caseta_id')->nullable()->constrained('casetas')->nullOnDelete();
            $table->foreignId('usuario_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('imagen_url')->nullable();
            $table->string('estado', 50)->default('Registrada y con paso');
            $table->integer('pasajeros')->default(1);
            $table->timestamps();
        });

        // alertas(id, paso_id, tipo, atendida, created_at)
        Schema::create('alertas', function (Blueprint $table) {
            $table->id();
            $table->foreignId('paso_id')->nullable()->constrained('pasos')->cascadeOnDelete();
            $table->string('tipo'); // 'placa_no_registrada', 'sin_saldo', etc.
            $table->string('mensaje')->nullable();
            $table->boolean('atendida')->default(false);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('alertas');
        Schema::dropIfExists('pasos');
        Schema::dropIfExists('tarifas');
        Schema::dropIfExists('casetas');
        Schema::dropIfExists('vehiculos');
    }
};

